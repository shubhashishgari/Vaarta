# Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
# tts.py - Text to Speech Engine
# Primary: ElevenLabs (natural voice with gender matching)
# Fallback: gTTS (free, no API key needed)
# Returns MP3 bytes for the server to send to the Flutter client

import os
import io
import threading
from typing import Optional
from dotenv import load_dotenv
from gtts import gTTS
from elevenlabs import VoiceSettings
from elevenlabs.client import ElevenLabs

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))

# --- Configuration ---
ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY")

# ElevenLabs voice IDs matched by gender
# Both voices use eleven_multilingual_v2 so they handle all Indian languages
ELEVENLABS_VOICES = {
    "male":   "pNInz6obpgDQGcFmaJgB",   # Adam
    "female": "21m00Tcm4TlvDq8ikWAM",   # Rachel
}

# gTTS language codes
GTTS_LANGUAGE_CODES = {
    "hi": "hi",
    "bn": "bn",
    "mr": "mr",
    "te": "te",
    "ta": "ta",
    "gu": "gu",
    "ur": "ur",
    "kn": "kn",
    "or": "or",
    "ml": "ml",
    "en": "en",
}


class TextToSpeech:
    """
    Vaarta's voice output engine.
    Generates MP3 audio bytes with gender-matched voice.
    Uses ElevenLabs for natural voice, falls back to gTTS.
    """

    def __init__(self):
        self.use_elevenlabs = bool(ELEVENLABS_API_KEY)
        self._lock = threading.Lock()
        self._last_spoken = ""
        self._last_language = "en"
        self._last_gender = "male"
        self._last_audio: Optional[bytes] = None

        if self.use_elevenlabs:
            self.client = ElevenLabs(api_key=ELEVENLABS_API_KEY)
            print("[Vaarta TTS] ElevenLabs ready.")
        else:
            print("[Vaarta TTS] No ElevenLabs key found. Using gTTS fallback.")

    # ------------------------------------------------------------------
    # ElevenLabs
    # ------------------------------------------------------------------

    def _generate_elevenlabs(
        self,
        text: str,
        language: str,
        gender: str = "male"
    ) -> Optional[bytes]:
        """Generate MP3 bytes using ElevenLabs with gender matched voice."""
        try:
            voice_id = ELEVENLABS_VOICES.get(gender, ELEVENLABS_VOICES["male"])

            audio_generator = self.client.text_to_speech.convert(
                voice_id=voice_id,
                text=text,
                model_id="eleven_multilingual_v2",
                voice_settings=VoiceSettings(
                    stability=0.3,
                    similarity_boost=0.8,
                    style=0.5,
                    use_speaker_boost=True
                )
            )

            audio_bytes = b"".join(audio_generator)
            return audio_bytes if audio_bytes else None

        except Exception as e:
            print(f"[Vaarta TTS] ElevenLabs error: {e}")
            return None

    # ------------------------------------------------------------------
    # gTTS Fallback
    # ------------------------------------------------------------------

    def _generate_gtts(self, text: str, language: str) -> Optional[bytes]:
        """Generate MP3 bytes using gTTS (free fallback)."""
        try:
            lang_code = GTTS_LANGUAGE_CODES.get(language, "en")
            tts = gTTS(text=text, lang=lang_code, slow=False)
            buffer = io.BytesIO()
            tts.write_to_fp(buffer)
            return buffer.getvalue()
        except Exception as e:
            print(f"[Vaarta TTS] gTTS error: {e}")
            return None

    # ------------------------------------------------------------------
    # Public Interface
    # ------------------------------------------------------------------

    def generate(
        self,
        text: str,
        language: str,
        gender: str = "male"
    ) -> Optional[bytes]:
        """
        Generate TTS audio as MP3 bytes.
        Tries ElevenLabs first with gender matched voice, falls back to gTTS.
        Returns MP3 bytes or None on failure.
        """
        if not text or not text.strip():
            return None

        with self._lock:
            print(f"[Vaarta TTS] Generating ({language}, {gender}): {text[:60]}...")

            audio_bytes = None
            if self.use_elevenlabs:
                audio_bytes = self._generate_elevenlabs(text, language, gender)
                if not audio_bytes:
                    print("[Vaarta TTS] Falling back to gTTS...")

            if not audio_bytes:
                audio_bytes = self._generate_gtts(text, language)

            if audio_bytes:
                # Cache for replay
                self._last_spoken = text
                self._last_language = language
                self._last_gender = gender
                self._last_audio = audio_bytes

            return audio_bytes

    def generate_replay(self) -> Optional[bytes]:
        """Return cached audio bytes from the last generation, or regenerate."""
        if self._last_audio:
            return self._last_audio
        if self._last_spoken:
            return self.generate(
                self._last_spoken, self._last_language, self._last_gender
            )
        return None


# ------------------------------------------------------------------
# Quick Test
# ------------------------------------------------------------------
if __name__ == "__main__":
    tts = TextToSpeech()

    test_cases = [
        ("Hello, I am Vaarta. I will help you communicate.", "en", "female"),
        ("Namaste, main Vaarta hoon.", "hi", "male"),
    ]

    print("\nTesting Vaarta TTS...\n")
    for text, lang, gender in test_cases:
        print(f"[{lang}] [{gender}] {text}")
        audio = tts.generate(text, lang, gender)
        if audio:
            print(f"  Generated {len(audio)} bytes of MP3 audio")
        else:
            print("  Failed to generate audio")
        print()
    print("TTS test complete.")
