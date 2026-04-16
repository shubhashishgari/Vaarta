# Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
# clarify.py - Proactive Clarification Engine
# Sits between STT output and translation input
# Flags low-confidence transcriptions and domain-critical keywords for user confirmation

import json
import os
import time
from dataclasses import dataclass
from typing import Optional

from stt import TranscriptionResult

# --- Paths ---
VOCAB_DIR = os.path.join(os.path.dirname(__file__), "vocabulary")
PERSONAL_VOCAB_PATH = os.path.join(VOCAB_DIR, "personal.json")
MEDICAL_VOCAB_PATH = os.path.join(VOCAB_DIR, "medical.json")
TRANSPORT_VOCAB_PATH = os.path.join(VOCAB_DIR, "transport.json")

# --- Configuration ---
MIN_CONFIDENCE = 0.15


@dataclass
class ClarificationResult:
    """Holds the result of a clarification check."""
    original_text: str          # Text as received from STT
    final_text: str             # Text after clarification (original or corrected)
    was_clarified: bool         # True if clarification was triggered
    correction_saved: bool      # True if a new correction was saved to personal.json
    trigger_reason: str = ""    # Why clarification was triggered


class ClarificationEngine:
    """
    Vaarta's proactive clarification engine.
    Checks transcriptions against confidence thresholds, domain keywords,
    and known mangled patterns before passing to translation.
    """

    def __init__(self):
        self.medical_keywords: set = set()
        self.transport_keywords: set = set()
        self.personal_vocab: dict = {}
        self._load_vocabularies()
        print("[Vaarta Clarify] Clarification engine ready.")

    # ------------------------------------------------------------------
    # Vocabulary Loading
    # ------------------------------------------------------------------

    def _load_vocabularies(self):
        """Load all vocabulary packs and build keyword sets."""
        # Load medical keywords
        self.medical_keywords = self._load_keyword_set(MEDICAL_VOCAB_PATH)
        print(f"[Vaarta Clarify] Loaded {len(self.medical_keywords)} medical keywords.")

        # Load transport keywords
        self.transport_keywords = self._load_keyword_set(TRANSPORT_VOCAB_PATH)
        print(f"[Vaarta Clarify] Loaded {len(self.transport_keywords)} transport keywords.")

        # Load personal vocab (known mangled patterns)
        self._reload_personal_vocab()

    def _load_keyword_set(self, path: str) -> set:
        """Load a vocabulary JSON and extract all keywords (English keys + all translations)."""
        keywords = set()
        if not os.path.exists(path):
            return keywords
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            for english_term, translations in data.items():
                # Add the English key
                keywords.add(english_term.lower())
                # Add all translated terms
                if isinstance(translations, dict):
                    for lang_code, term in translations.items():
                        if isinstance(term, str) and term.strip():
                            keywords.add(term.lower())
        except Exception as e:
            print(f"[Vaarta Clarify] Error loading {path}: {e}")
        return keywords

    def _reload_personal_vocab(self):
        """Reload personal vocabulary from file."""
        if os.path.exists(PERSONAL_VOCAB_PATH):
            try:
                with open(PERSONAL_VOCAB_PATH, "r", encoding="utf-8") as f:
                    self.personal_vocab = json.load(f)
            except Exception:
                self.personal_vocab = {}
        else:
            self.personal_vocab = {}

    # ------------------------------------------------------------------
    # Trigger Checks
    # ------------------------------------------------------------------

    def _check_low_confidence(self, result: TranscriptionResult) -> bool:
        """Trigger 1: confidence below threshold."""
        return result.confidence < MIN_CONFIDENCE

    def _check_domain_keywords(self, text: str, active_domain: str) -> bool:
        """Trigger 2: text contains critical domain keywords."""
        text_lower = text.lower()
        words = text_lower.split()

        if active_domain == "medical":
            for word in words:
                if word in self.medical_keywords:
                    return True
            # Also check multi-word phrases
            for keyword in self.medical_keywords:
                if " " in keyword and keyword in text_lower:
                    return True

        elif active_domain == "transport":
            for word in words:
                if word in self.transport_keywords:
                    return True
            for keyword in self.transport_keywords:
                if " " in keyword and keyword in text_lower:
                    return True

        return False

    def _check_mangled_pattern(self, text: str) -> bool:
        """Trigger 3: text matches a known mangled pattern in personal vocab."""
        if not self.personal_vocab:
            return False
        text_lower = text.lower()
        for wrong in self.personal_vocab.keys():
            if wrong.lower() in text_lower:
                return True
        return False

    # ------------------------------------------------------------------
    # Core Check
    # ------------------------------------------------------------------

    def check(
        self,
        result: TranscriptionResult,
        active_domain: str = "general"
    ) -> ClarificationResult:
        """
        Check a transcription result against all clarification triggers.
        Must complete in under 500ms.

        Returns ClarificationResult with was_clarified=True if any trigger fires.
        In API mode, the caller handles presenting the clarification to the user.
        """
        start_time = time.time()
        text = result.text
        trigger_reason = ""

        # Trigger 1: Low confidence
        if self._check_low_confidence(result):
            trigger_reason = f"low_confidence ({result.confidence:.0%})"

        # Trigger 2: Domain keywords (only check if not already triggered)
        elif active_domain != "general" and self._check_domain_keywords(text, active_domain):
            trigger_reason = f"domain_keyword ({active_domain})"

        # Trigger 3: Known mangled pattern
        elif self._check_mangled_pattern(text):
            trigger_reason = "known_mangled_pattern"

        elapsed = time.time() - start_time
        if elapsed > 0.5:
            print(f"[Vaarta Clarify] WARNING: Check took {elapsed:.3f}s (target <0.5s)")

        if trigger_reason:
            return ClarificationResult(
                original_text=text,
                final_text=text,  # Will be updated if user provides correction
                was_clarified=True,
                correction_saved=False,
                trigger_reason=trigger_reason
            )

        return ClarificationResult(
            original_text=text,
            final_text=text,
            was_clarified=False,
            correction_saved=False
        )

    # ------------------------------------------------------------------
    # Correction Handling
    # ------------------------------------------------------------------

    def accept_correction(
        self,
        original_text: str,
        corrected_text: str,
        translator=None
    ) -> ClarificationResult:
        """
        Accept a user correction and save it to personal vocabulary.
        Call this when the user provides a correction via the clarification prompt.

        Args:
            original_text: The text that was flagged
            corrected_text: The user's correction
            translator: Optional Translator instance to reload vocab on
        """
        correction_saved = False

        if corrected_text and corrected_text.strip() != original_text.strip():
            # Save correction to personal.json (case-insensitive, stored lowercase)
            self._save_correction(original_text.lower().strip(), corrected_text.strip())
            correction_saved = True

            # Reload translator's personal vocab if available
            if translator is not None:
                translator.reload_personal_vocab()

            # Reload our own copy
            self._reload_personal_vocab()

        return ClarificationResult(
            original_text=original_text,
            final_text=corrected_text if corrected_text else original_text,
            was_clarified=True,
            correction_saved=correction_saved
        )

    def _save_correction(self, wrong: str, correct: str):
        """Save a wrong → correct mapping to personal.json."""
        try:
            # Load current vocab
            vocab = {}
            if os.path.exists(PERSONAL_VOCAB_PATH):
                with open(PERSONAL_VOCAB_PATH, "r", encoding="utf-8") as f:
                    vocab = json.load(f)

            # Add new correction
            vocab[wrong] = correct

            # Save back
            with open(PERSONAL_VOCAB_PATH, "w", encoding="utf-8") as f:
                json.dump(vocab, f, ensure_ascii=False, indent=2)

            print(f"[Vaarta Clarify] Saved correction: '{wrong}' → '{correct}'")
        except Exception as e:
            print(f"[Vaarta Clarify] Error saving correction: {e}")

    def get_domain_keywords(self, domain: str) -> set:
        """Return keywords for a specific domain."""
        if domain == "medical":
            return self.medical_keywords
        elif domain == "transport":
            return self.transport_keywords
        return set()


# ------------------------------------------------------------------
# Quick Test
# ------------------------------------------------------------------
if __name__ == "__main__":
    engine = ClarificationEngine()

    # Test with a low-confidence result
    test_result = TranscriptionResult(
        text="mujhe doctor ke paas jaana hai",
        language="hi",
        language_name="Hindi",
        confidence=0.60,
        is_confident=False,
        is_supported_language=True,
        gender="male"
    )

    clarification = engine.check(test_result, active_domain="medical")
    print(f"\nTest 1 - Low confidence:")
    print(f"  Text: {clarification.original_text}")
    print(f"  Triggered: {clarification.was_clarified}")
    print(f"  Reason: {clarification.trigger_reason}")

    # Test with high confidence + domain keyword
    test_result2 = TranscriptionResult(
        text="I need an injection for the fever",
        language="en",
        language_name="English",
        confidence=0.92,
        is_confident=True,
        is_supported_language=True,
        gender="female"
    )

    clarification2 = engine.check(test_result2, active_domain="medical")
    print(f"\nTest 2 - Domain keyword:")
    print(f"  Text: {clarification2.original_text}")
    print(f"  Triggered: {clarification2.was_clarified}")
    print(f"  Reason: {clarification2.trigger_reason}")

    # Test saving a correction
    result = engine.accept_correction("doktar", "doctor")
    print(f"\nTest 3 - Correction saved: {result.correction_saved}")
