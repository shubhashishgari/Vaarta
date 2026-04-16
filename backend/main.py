# Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
# main.py - FastAPI Server
# Orchestrates the full pipeline: STT → Clarify → Translate → TTS
# WebSocket for real-time audio streaming, REST for config endpoints

import os
import sys
import json
import base64
import asyncio
import numpy as np
from pathlib import Path
from typing import Optional
from dataclasses import asdict

# Force UTF-8 for stdout/stderr so Devanagari/Tamil/Telugu text in log statements
# doesn't crash the session handler on Windows (default console is cp1252).
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from dotenv import load_dotenv

# Load .env explicitly from backend/.env
BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(dotenv_path=os.path.join(BACKEND_DIR, ".env"))

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from stt import SpeechToText, TranscriptionResult, SUPPORTED_LANGUAGES, SAMPLE_RATE, CHUNK_SIZE
from Translate import Translator
from tts import TextToSpeech
from clarify import ClarificationEngine

# ------------------------------------------------------------------
# App Setup
# ------------------------------------------------------------------

app = FastAPI(
    title="Vaarta",
    description="Real-Time Multilingual Voice Translation System",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ------------------------------------------------------------------
# Initialize Pipeline Components
# ------------------------------------------------------------------

print("[Vaarta] Initializing pipeline components...")
stt_engine = SpeechToText()
translator = Translator()
tts_engine = TextToSpeech()
clarify_engine = ClarificationEngine()
print("[Vaarta] All components ready.")

# ------------------------------------------------------------------
# Vocabulary Paths
# ------------------------------------------------------------------

VOCAB_DIR = os.path.join(BACKEND_DIR, "vocabulary")
PERSONAL_VOCAB_PATH = os.path.join(VOCAB_DIR, "personal.json")


# ------------------------------------------------------------------
# Session State
# ------------------------------------------------------------------

class SpeakerState:
    """Tracks per-speaker state within a session."""
    def __init__(self):
        self.language: Optional[str] = None
        self.language_name: Optional[str] = None
        self.gender: str = "male"
        self.last_text: str = ""


class SessionState:
    """Tracks state for a WebSocket session (two speakers)."""
    def __init__(self):
        self.speaker_a = SpeakerState()
        self.speaker_b = SpeakerState()
        self.active_speaker: str = "A"  # Which speaker is currently talking
        self.active_domain: str = "general"  # general, medical, transport
        self.is_active: bool = True
        self.audio_buffer: np.ndarray = np.array([], dtype=np.float32)


# Store active sessions
sessions: dict[str, SessionState] = {}


# ------------------------------------------------------------------
# REST Endpoints
# ------------------------------------------------------------------

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "service": "vaarta",
        "version": "1.0.0",
        "components": {
            "stt": "ready",
            "translator": "ready",
            "tts": "ready",
            "clarify": "ready"
        }
    }


@app.get("/languages")
async def get_languages():
    """Return list of supported languages."""
    return {
        "languages": SUPPORTED_LANGUAGES,
        "total_pairs": len(SUPPORTED_LANGUAGES) * (len(SUPPORTED_LANGUAGES) - 1),
        "pivot_language": "en"
    }


@app.get("/vocabulary")
async def get_vocabulary():
    """Return personal vocabulary contents."""
    try:
        if os.path.exists(PERSONAL_VOCAB_PATH):
            with open(PERSONAL_VOCAB_PATH, "r", encoding="utf-8") as f:
                vocab = json.load(f)
            return {"vocabulary": vocab, "count": len(vocab)}
        return {"vocabulary": {}, "count": 0}
    except Exception as e:
        return {"vocabulary": {}, "count": 0, "error": str(e)}


@app.delete("/vocabulary/{word}")
async def delete_vocabulary_word(word: str):
    """Remove a word from personal vocabulary."""
    try:
        if not os.path.exists(PERSONAL_VOCAB_PATH):
            return {"success": False, "error": "Vocabulary file not found"}

        with open(PERSONAL_VOCAB_PATH, "r", encoding="utf-8") as f:
            vocab = json.load(f)

        # Case-insensitive search
        word_lower = word.lower()
        key_to_delete = None
        for key in vocab:
            if key.lower() == word_lower:
                key_to_delete = key
                break

        if key_to_delete is None:
            return {"success": False, "error": f"Word '{word}' not found"}

        del vocab[key_to_delete]

        with open(PERSONAL_VOCAB_PATH, "w", encoding="utf-8") as f:
            json.dump(vocab, f, ensure_ascii=False, indent=2)

        # Reload translator's personal vocab
        translator.reload_personal_vocab()

        return {"success": True, "deleted": word, "remaining": len(vocab)}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ------------------------------------------------------------------
# WebSocket Pipeline
# ------------------------------------------------------------------

async def process_audio_chunk(
    audio_data: np.ndarray,
    session: SessionState,
    websocket: WebSocket
):
    """
    Process a single audio chunk through the full pipeline.
    STT → Clarify → Translate → TTS
    """
    try:
        # Step 1: Speech to Text
        result = stt_engine.transcribe_audio_data(audio_data)
        if result is None or not result.text:
            return

        print(f"[Vaarta] STT: [{result.language_name}] [{result.gender}] "
              f"({result.confidence:.0%}) {result.text}")

        # Update speaker state
        current_speaker = session.speaker_a if session.active_speaker == "A" else session.speaker_b
        other_speaker = session.speaker_b if session.active_speaker == "A" else session.speaker_a

        current_speaker.language = result.language
        current_speaker.language_name = result.language_name
        current_speaker.gender = result.gender
        current_speaker.last_text = result.text

        # Send transcription to frontend
        await websocket.send_json({
            "type": "transcription",
            "speaker": session.active_speaker,
            "text": result.text,
            "language": result.language,
            "language_name": result.language_name,
            "confidence": result.confidence,
            "gender": result.gender
        })

        # Step 2: Clarification Check
        clarification = clarify_engine.check(result, active_domain=session.active_domain)

        if clarification.was_clarified:
            print(f"[Vaarta] Clarification triggered: {clarification.trigger_reason}")
            # Send clarification request to frontend
            await websocket.send_json({
                "type": "clarification_request",
                "text": clarification.original_text,
                "reason": clarification.trigger_reason,
                "speaker": session.active_speaker
            })
            # Don't proceed with translation yet — wait for user response
            return

        # Step 3: Translate
        text_to_translate = clarification.final_text

        # Determine target language — translate to the OTHER speaker's language
        target_language = other_speaker.language
        if target_language is None:
            # If other speaker's language not yet detected, default to English
            target_language = "en" if result.language != "en" else "hi"

        if result.language == target_language:
            # Same language, no translation needed
            await websocket.send_json({
                "type": "translation",
                "speaker": session.active_speaker,
                "original_text": result.text,
                "translated_text": result.text,
                "source_language": result.language,
                "target_language": target_language,
                "same_language": True
            })
            return

        translation = translator.translate(
            text_to_translate,
            source_language=result.language,
            target_language=target_language
        )

        print(f"[Vaarta] Translation: {translation.translated_text}")

        # Send translation to frontend
        await websocket.send_json({
            "type": "translation",
            "speaker": session.active_speaker,
            "original_text": translation.original_text,
            "translated_text": translation.translated_text,
            "source_language": translation.source_language,
            "target_language": translation.target_language,
            "source_language_name": translation.source_language_name,
            "target_language_name": translation.target_language_name,
            "preserved_words": translation.preserved_words,
            "applied_corrections": translation.applied_corrections,
            "used_pivot": translation.used_pivot,
            "same_language": False
        })

        # Step 4: TTS — generate audio bytes and include in response
        audio_bytes = tts_engine.generate(
            translation.translated_text,
            language=target_language,
            gender=result.gender
        )
        if audio_bytes:
            await websocket.send_json({
                "type": "audio",
                "audio": base64.b64encode(audio_bytes).decode("utf-8")
            })

    except Exception as e:
        print(f"[Vaarta] Pipeline error: {e}")
        try:
            await websocket.send_json({
                "type": "error",
                "message": str(e)
            })
        except Exception:
            pass


@app.websocket("/ws/session")
async def websocket_session(websocket: WebSocket):
    """
    WebSocket endpoint for real-time audio streaming.
    Handles the full translation pipeline for a two-speaker session.
    """
    await websocket.accept()
    session_id = str(id(websocket))
    session = SessionState()
    sessions[session_id] = session

    print(f"[Vaarta] Session {session_id} connected.")

    try:
        await websocket.send_json({
            "type": "session_start",
            "session_id": session_id,
            "message": "Connected to Vaarta. Start speaking."
        })

        while session.is_active:
            try:
                message = await websocket.receive()

                # Handle binary audio data
                if "bytes" in message:
                    raw_bytes = message["bytes"]
                    try:
                        # Flutter sends PCM 16-bit signed integer audio
                        # Convert to float32 [-1.0, 1.0] for Whisper
                        audio_int16 = np.frombuffer(raw_bytes, dtype=np.int16)
                        audio_float32 = audio_int16.astype(np.float32) / 32768.0

                        # Accumulate audio — process as ONE chunk on stop_speaking
                        # for clean full-sentence transcription (push-to-talk flow)
                        session.audio_buffer = np.concatenate([session.audio_buffer, audio_float32])

                        # Safety cap: if user speaks >30s without stopping, process what we have
                        max_buffer_samples = SAMPLE_RATE * 30
                        if len(session.audio_buffer) >= max_buffer_samples:
                            chunk = session.audio_buffer[:max_buffer_samples]
                            session.audio_buffer = session.audio_buffer[max_buffer_samples:]
                            await process_audio_chunk(chunk, session, websocket)
                    except Exception as e:
                        print(f"[Vaarta] Audio processing error: {e}")

                # Handle JSON text messages (commands from frontend)
                elif "text" in message:
                    try:
                        data = json.loads(message["text"])
                        msg_type = data.get("type", "")

                        if msg_type == "stop_speaking":
                            # Flush remaining audio buffer — process full utterance as one chunk
                            if len(session.audio_buffer) > SAMPLE_RATE * 0.2:  # At least 0.2s of audio
                                chunk = session.audio_buffer.copy()
                                session.audio_buffer = np.array([], dtype=np.float32)
                                await process_audio_chunk(chunk, session, websocket)
                            else:
                                session.audio_buffer = np.array([], dtype=np.float32)
                            await websocket.send_json({"type": "processing_complete"})

                        elif msg_type == "switch_speaker":
                            # Toggle active speaker
                            session.active_speaker = "B" if session.active_speaker == "A" else "A"
                            await websocket.send_json({
                                "type": "speaker_switched",
                                "active_speaker": session.active_speaker
                            })

                        elif msg_type == "set_domain":
                            # Change active domain
                            domain = data.get("domain", "general")
                            if domain in ("general", "medical", "transport"):
                                session.active_domain = domain
                                await websocket.send_json({
                                    "type": "domain_changed",
                                    "domain": session.active_domain
                                })

                        elif msg_type == "clarification_response":
                            # User responded to a clarification prompt
                            original = data.get("original_text", "")
                            corrected = data.get("corrected_text", "")
                            accepted = data.get("accepted", False)

                            if accepted and not corrected:
                                # User accepted the original text
                                corrected = original

                            if corrected:
                                # Save correction if different from original
                                clar_result = clarify_engine.accept_correction(
                                    original, corrected, translator=translator
                                )

                                # Now translate the corrected text
                                current_speaker = (session.speaker_a
                                                   if session.active_speaker == "A"
                                                   else session.speaker_b)
                                other_speaker = (session.speaker_b
                                                 if session.active_speaker == "A"
                                                 else session.speaker_a)

                                source_lang = current_speaker.language or "en"
                                target_lang = other_speaker.language or (
                                    "en" if source_lang != "en" else "hi"
                                )

                                translation = translator.translate(
                                    clar_result.final_text,
                                    source_language=source_lang,
                                    target_language=target_lang
                                )

                                await websocket.send_json({
                                    "type": "translation",
                                    "speaker": session.active_speaker,
                                    "original_text": translation.original_text,
                                    "translated_text": translation.translated_text,
                                    "source_language": translation.source_language,
                                    "target_language": translation.target_language,
                                    "source_language_name": translation.source_language_name,
                                    "target_language_name": translation.target_language_name,
                                    "preserved_words": translation.preserved_words,
                                    "applied_corrections": translation.applied_corrections,
                                    "used_pivot": translation.used_pivot,
                                    "was_corrected": clar_result.correction_saved,
                                    "same_language": False
                                })

                                audio_bytes = tts_engine.generate(
                                    translation.translated_text,
                                    language=target_lang,
                                    gender=current_speaker.gender
                                )
                                if audio_bytes:
                                    await websocket.send_json({
                                        "type": "audio",
                                        "audio": base64.b64encode(audio_bytes).decode("utf-8")
                                    })

                        elif msg_type == "replay":
                            # Replay last translation
                            audio_bytes = tts_engine.generate_replay()
                            if audio_bytes:
                                await websocket.send_json({
                                    "type": "audio",
                                    "audio": base64.b64encode(audio_bytes).decode("utf-8")
                                })
                            await websocket.send_json({
                                "type": "replay_started"
                            })

                        elif msg_type == "set_speaker_language":
                            # Manually set a speaker's language (optional override)
                            speaker = data.get("speaker", "A")
                            language = data.get("language", "")
                            if speaker == "A" and language in SUPPORTED_LANGUAGES:
                                session.speaker_a.language = language
                                session.speaker_a.language_name = SUPPORTED_LANGUAGES[language]
                            elif speaker == "B" and language in SUPPORTED_LANGUAGES:
                                session.speaker_b.language = language
                                session.speaker_b.language_name = SUPPORTED_LANGUAGES[language]

                    except json.JSONDecodeError:
                        pass

            except WebSocketDisconnect:
                break
            except Exception as e:
                print(f"[Vaarta] Session error: {e}")
                break

    except Exception as e:
        print(f"[Vaarta] Session {session_id} error: {e}")
    finally:
        session.is_active = False
        sessions.pop(session_id, None)
        print(f"[Vaarta] Session {session_id} disconnected.")


# ------------------------------------------------------------------
# Startup
# ------------------------------------------------------------------

@app.on_event("startup")
async def startup_event():
    """Load vocabulary packs and confirm pipeline readiness."""
    print("[Vaarta] ========================================")
    print("[Vaarta] VAARTA - Real-Time Voice Translation")
    print("[Vaarta] By Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi")
    print("[Vaarta] ========================================")
    print(f"[Vaarta] Supported languages: {len(SUPPORTED_LANGUAGES)}")
    print(f"[Vaarta] Translation pairs: {len(SUPPORTED_LANGUAGES) * (len(SUPPORTED_LANGUAGES) - 1)}")
    print(f"[Vaarta] Active domain: general")
    print("[Vaarta] Server ready. Waiting for connections...")


# ------------------------------------------------------------------
# Run
# ------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )
