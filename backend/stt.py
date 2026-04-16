# Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
# stt.py - Speech to Text Engine
# Uses faster-whisper for real-time transcription with language detection and gender detection

import numpy as np
import queue
import threading
from faster_whisper import WhisperModel
from dataclasses import dataclass, field
from typing import Optional, Callable

# pyaudio is only needed for the standalone local-mic test path (stt.start()
# and the __main__ block below). The FastAPI backend receives audio bytes from
# the phone over WebSocket and calls transcribe_audio_data() directly, so it
# doesn't need pyaudio. Make the import optional so the backend still runs on
# environments where pyaudio can't be installed (e.g. Python 3.14 without a
# C++ compiler for the prebuilt wheel).
try:
    import pyaudio  # type: ignore
    _PYAUDIO_AVAILABLE = True
except ImportError:
    pyaudio = None  # type: ignore
    _PYAUDIO_AVAILABLE = False

# --- Configuration ---
WHISPER_MODEL_SIZE = "small"      # Options: tiny, base, small, medium, large — report specifies "small"
SAMPLE_RATE = 16000               # Whisper expects 16kHz audio
CHUNK_DURATION = 3                # Seconds of audio per transcription chunk (report: 3-second chunked processing)
CHUNK_SIZE = SAMPLE_RATE * CHUNK_DURATION
SILENCE_THRESHOLD = 0.005         # Amplitude below this is considered silence (report: 0.005)
MIN_CONFIDENCE = 0.75             # Minimum confidence to accept transcription

# Context hint for Whisper — helps with Indian multilingual / code-switched speech
WHISPER_INITIAL_PROMPT = (
    "This is a conversation between two Indian speakers. "
    "Common languages include Hindi, Tamil, Telugu, Bengali, Marathi, "
    "Gujarati, Urdu, Kannada, Malayalam, Odia, and English. "
    "Speakers often mix English words like doctor, hospital, auto, bus, wifi, "
    "station, ticket, app, medicine, and office into their native language."
)

# Supported Vaarta languages (ISO 639-1 codes)
SUPPORTED_LANGUAGES = {
    "hi": "Hindi",
    "bn": "Bengali",
    "mr": "Marathi",
    "te": "Telugu",
    "ta": "Tamil",
    "gu": "Gujarati",
    "ur": "Urdu",
    "kn": "Kannada",
    "or": "Odia",
    "ml": "Malayalam",
    "en": "English"
}


@dataclass
class TranscriptionResult:
    """Holds the result of a single transcription chunk."""
    text: str                        # Transcribed text
    language: str                    # Detected language code (e.g. "hi", "ta")
    language_name: str               # Human-readable language name
    confidence: float                # Confidence score (0.0 to 1.0)
    is_confident: bool               # True if confidence >= MIN_CONFIDENCE
    is_supported_language: bool      # True if language is in SUPPORTED_LANGUAGES
    gender: str = "male"             # Detected speaker gender


class SpeechToText:
    """
    Real-time speech-to-text engine using faster-whisper.
    Continuously captures audio, detects language, gender, and transcribes.
    """

    def __init__(self, model_size: str = WHISPER_MODEL_SIZE):
        print(f"[Vaarta STT] Loading Whisper model: {model_size}")
        self.model = WhisperModel(
            model_size,
            device="cpu",
            compute_type="int8"
        )
        print("[Vaarta STT] Model loaded successfully.")

        self.audio_queue = queue.Queue()
        self.is_running = False
        self._audio_thread = None
        self._process_thread = None

    # ------------------------------------------------------------------
    # Audio Capture
    # ------------------------------------------------------------------

    def _capture_audio(self):
        """Continuously captures microphone audio and puts chunks in queue."""
        pa = pyaudio.PyAudio()
        stream = pa.open(
            format=pyaudio.paFloat32,
            channels=1,
            rate=SAMPLE_RATE,
            input=True,
            frames_per_buffer=1024
        )
        print("[Vaarta STT] Microphone open. Listening...")

        buffer = []
        buffer_samples = 0

        while self.is_running:
            try:
                data = stream.read(1024, exception_on_overflow=False)
                chunk = np.frombuffer(data, dtype=np.float32)
                buffer.append(chunk)
                buffer_samples += len(chunk)

                if buffer_samples >= CHUNK_SIZE:
                    audio_array = np.concatenate(buffer)
                    self.audio_queue.put(audio_array[:CHUNK_SIZE])
                    print(f"[DEBUG] Audio chunk added to queue")
                    leftover = audio_array[CHUNK_SIZE:]
                    buffer = [leftover] if len(leftover) > 0 else []
                    buffer_samples = len(leftover)
            except Exception:
                continue

        stream.stop_stream()
        stream.close()
        pa.terminate()
        print("[Vaarta STT] Microphone closed.")

    # ------------------------------------------------------------------
    # Gender Detection
    # ------------------------------------------------------------------

    def _detect_gender(self, audio: np.ndarray) -> str:
        """
        Detect speaker gender from audio pitch.
        Returns 'male' or 'female'.
        """
        try:
            import librosa
            pitches, magnitudes = librosa.piptrack(
                y=audio,
                sr=SAMPLE_RATE,
                fmin=50,
                fmax=400
            )
            pitch_values = []
            for t in range(pitches.shape[1]):
                index = magnitudes[:, t].argmax()
                pitch = pitches[index, t]
                if pitch > 0:
                    pitch_values.append(pitch)

            if not pitch_values:
                return "male"

            avg_pitch = float(np.mean(pitch_values))
            return "female" if avg_pitch > 165 else "male"

        except Exception:
            return "male"

    # ------------------------------------------------------------------
    # Silence Detection
    # ------------------------------------------------------------------

    def _is_silence(self, audio: np.ndarray) -> bool:
        """Returns True if the audio chunk is mostly silence."""
        return float(np.abs(audio).mean()) < SILENCE_THRESHOLD

    # ------------------------------------------------------------------
    # Transcription
    # ------------------------------------------------------------------

    def _transcribe_chunk(self, audio: np.ndarray) -> Optional[TranscriptionResult]:
        """Transcribes a single audio chunk and returns a TranscriptionResult."""
        if self._is_silence(audio):
            print(f"[DEBUG] Silence detected, skipping chunk")
            return None
        print(f"[DEBUG] Processing audio chunk...")

        segments, info = self.model.transcribe(
            audio,
            beam_size=10,
            language=None,
            vad_filter=True,
            vad_parameters=dict(
                min_silence_duration_ms=500,
                speech_pad_ms=200,
            ),
            initial_prompt=WHISPER_INITIAL_PROMPT,
            condition_on_previous_text=False,
            temperature=0.0,
            no_speech_threshold=0.4,
            compression_ratio_threshold=2.4,
        )

        # Force consume the entire generator immediately
        segments_list = list(segments)
        text_parts = [s.text.strip() for s in segments_list]
        full_text = " ".join(text_parts).strip()

        print(f"[DEBUG] Whisper returned: '{full_text}'")

        if not full_text:
            print(f"[DEBUG] Empty text, skipping")
            return None

        detected_lang = info.language
        lang_prob = float(info.language_probability)
        lang_name = SUPPORTED_LANGUAGES.get(detected_lang, detected_lang.upper())
        gender = self._detect_gender(audio)

        return TranscriptionResult(
            text=full_text,
            language=detected_lang,
            language_name=lang_name,
            confidence=lang_prob,
            is_confident=lang_prob >= MIN_CONFIDENCE,
            is_supported_language=detected_lang in SUPPORTED_LANGUAGES,
            gender=gender
        )

    def _process_audio(self, on_transcription: Callable[[TranscriptionResult], None]):
        """Continuously processes audio from the queue and calls callback."""
        while self.is_running:
            try:
                audio = self.audio_queue.get(timeout=1.0)
                result = self._transcribe_chunk(audio)
                if result and result.text:
                    on_transcription(result)
            except queue.Empty:
                continue

    # ------------------------------------------------------------------
    # Public Interface
    # ------------------------------------------------------------------

    def start(self, on_transcription: Callable[[TranscriptionResult], None]):
        """Start listening and transcribing."""
        if not _PYAUDIO_AVAILABLE:
            raise RuntimeError(
                "pyaudio is not installed — local-mic capture isn't available. "
                "The FastAPI backend doesn't need this; it uses transcribe_audio_data() "
                "with audio bytes from the WebSocket client. Install pyaudio only if "
                "you want to run stt.py standalone."
            )
        self.is_running = True

        self._audio_thread = threading.Thread(
            target=self._capture_audio,
            daemon=True
        )
        self._process_thread = threading.Thread(
            target=self._process_audio,
            args=(on_transcription,),
            daemon=True
        )

        self._audio_thread.start()
        self._process_thread.start()
        print("[Vaarta STT] Started.")

    def stop(self):
        """Stop listening and transcribing."""
        self.is_running = False
        if self._audio_thread:
            self._audio_thread.join(timeout=3)
        if self._process_thread:
            self._process_thread.join(timeout=3)
        print("[Vaarta STT] Stopped.")

    def transcribe_audio_data(self, audio: np.ndarray) -> Optional[TranscriptionResult]:
        """Transcribe a single numpy audio array directly (for API use)."""
        return self._transcribe_chunk(audio)


# ------------------------------------------------------------------
# Quick Test
# ------------------------------------------------------------------
if __name__ == "__main__":
    import time

    results = []

    def handle_result(result: TranscriptionResult):
        results.append(result)
        print(f"\n[{result.language_name}] [{result.gender}] ({result.confidence:.0%} confident)")
        print(f"  Text: {result.text}")
        if not result.is_supported_language:
            print(f"  Warning: Language '{result.language}' not in Vaarta supported list")
        if not result.is_confident:
            print(f"  Warning: Low confidence, may need clarification")

    stt = SpeechToText(model_size="small")
    stt.start(on_transcription=handle_result)

    print("\nSpeak into your microphone. Recording for 20 seconds...\n")
    time.sleep(3)   # Wait for mic to fully open
    print("Mic ready. Speak now.\n")
    time.sleep(20)  # Listen for 20 seconds
    stt.stop()
    time.sleep(5)   # Wait for remaining chunks
    print(f"\n--- Session ended. Captured {len(results)} transcription(s). ---")