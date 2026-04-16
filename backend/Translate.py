# Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
# translate.py - Translation Engine with Code-Switching Handler
# Handles translation across 10 Indian languages + English
# Intelligently preserves English words embedded in Indian language speech

import re
import json
import os
from deep_translator import GoogleTranslator
from dataclasses import dataclass
from typing import Optional

# --- Language Configuration ---
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

# Pivot language for pairs without direct translation support
# English is used because Google Translate has the strongest X↔English models,
# avoiding hidden double-hops (X→English→Hindi→English→Y) that Hindi pivot causes
# e.g. Tamil → Odia goes Tamil → English → Odia
PIVOT_LANGUAGE = "en"

# Path to personal vocabulary file (learned corrections)
PERSONAL_VOCAB_PATH = os.path.join(
    os.path.dirname(__file__), "vocabulary", "personal.json"
)

# ------------------------------------------------------------------
# English words commonly used in Indian languages (code-switching)
# These are preserved as-is during translation
# ------------------------------------------------------------------
UNIVERSAL_ENGLISH_WORDS = {
    # Transport
    "auto", "cab", "bike", "bus", "metro", "train", "taxi",
    "uber", "ola", "rapido", "signal", "flyover", "highway",
    "toll", "parking", "petrol", "diesel", "pump",

    # Medical
    "doctor", "hospital", "clinic", "medicine", "tablet",
    "injection", "operation", "surgery", "icu", "ot", "opd",
    "bp", "sugar", "fever", "report", "scan", "x-ray", "mri",
    "ambulance", "emergency", "ward", "bed",

    # Technology
    "phone", "mobile", "laptop", "computer", "internet",
    "wifi", "charger", "battery", "app", "online", "offline",
    "password", "otp", "upi", "gpay", "paytm",

    # Daily life
    "mall", "shop", "market", "hotel", "restaurant", "cafe",
    "office", "school", "college", "university", "class",
    "exam", "result", "fees", "receipt", "bill", "gst",
    "emi", "loan", "bank", "atm", "card", "cash",

    # Common adjectives/words Indians use in English
    "ok", "okay", "fine", "nice", "good", "bad", "best",
    "worst", "super", "awesome", "cool", "no", "yes",

    # Proper nouns that should never be translated
    "india", "delhi", "mumbai", "bangalore", "bengaluru",
    "chennai", "hyderabad", "kolkata", "pune", "ahmedabad",
    "jaipur", "lucknow", "goa", "kerala", "kashmir",

    # Brands / Products
    "amazon", "flipkart", "zomato", "swiggy", "youtube",
    "instagram", "whatsapp", "google", "facebook",

    # Shampoo, toothpaste type words
    "shampoo", "toothpaste", "soap", "cream", "lotion",
    "powder", "spray", "gel", "serum",
}


@dataclass
class TranslationResult:
    """Holds the result of a translation operation."""
    original_text: str           # Input text before translation
    translated_text: str         # Final translated output
    source_language: str         # Detected source language code
    target_language: str         # Target language code
    source_language_name: str    # Human-readable source language
    target_language_name: str    # Human-readable target language
    used_pivot: bool             # True if translation went through a pivot language
    preserved_words: list        # English words that were kept as-is
    applied_corrections: list    # Personal vocab corrections that were applied


class Translator:
    """
    Vaarta's translation engine.
    Handles code-switching, vocabulary correction, and pivot routing.
    """

    def __init__(self):
        self.personal_vocab = self._load_personal_vocab()
        print("[Vaarta Translate] Translation engine ready.")

    # ------------------------------------------------------------------
    # Vocabulary Management
    # ------------------------------------------------------------------

    def _load_personal_vocab(self) -> dict:
        """Load user's personal vocabulary corrections from file."""
        if os.path.exists(PERSONAL_VOCAB_PATH):
            with open(PERSONAL_VOCAB_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        return {}

    def reload_personal_vocab(self):
        """Reload personal vocab — call this after clarify.py saves a correction."""
        self.personal_vocab = self._load_personal_vocab()

    def _apply_personal_vocab(self, text: str) -> tuple[str, list]:
        """
        Apply personal vocabulary corrections to text.
        Returns (corrected_text, list_of_corrections_applied)
        """
        corrections_applied = []
        corrected = text

        for wrong, correct in self.personal_vocab.items():
            if wrong.lower() in corrected.lower():
                # Case-insensitive replacement
                pattern = re.compile(re.escape(wrong), re.IGNORECASE)
                corrected = pattern.sub(correct, corrected)
                corrections_applied.append(f"{wrong} → {correct}")

        return corrected, corrections_applied

    # ------------------------------------------------------------------
    # Code-Switching Handler
    # ------------------------------------------------------------------

    def _extract_english_words(self, text: str) -> set:
        """
        Find English words in the text that should be preserved.
        Returns set of words found.
        """
        words = re.findall(r'\b[a-zA-Z]+\b', text)
        preserved = set()
        for word in words:
            if word.lower() in UNIVERSAL_ENGLISH_WORDS:
                preserved.add(word)
        return preserved

    def _protect_english_words(self, text: str, preserved: set) -> tuple[str, dict]:
        """
        Replace preserved English words with placeholders before translation.
        Returns (protected_text, placeholder_map)
        """
        placeholder_map = {}
        protected = text

        for i, word in enumerate(preserved):
            placeholder = f"__VAARTA_{i}__"
            placeholder_map[placeholder] = word
            # Replace all case variants
            pattern = re.compile(re.escape(word), re.IGNORECASE)
            protected = pattern.sub(placeholder, protected)

        return protected, placeholder_map

    def _restore_english_words(self, text: str, placeholder_map: dict) -> str:
        """Restore English word placeholders back to original words."""
        restored = text
        for placeholder, word in placeholder_map.items():
            restored = restored.replace(placeholder, word)
        return restored

    # ------------------------------------------------------------------
    # Translation Core
    # ------------------------------------------------------------------

    def _needs_pivot(self, source: str, target: str) -> bool:
        """
        Determine if we need a pivot language.
        As stated in the Vaarta report, certain low-resource Indic pairs
        (e.g., Odia <-> Kannada, Tamil <-> Odia, Malayalam <-> Odia) produce
        weaker direct translations. We proactively pivot those through English.
        """
        if source == target:
            return False
        # Weak-direct pairs observed empirically — route via English for quality
        weak_pairs = {
            ("or", "kn"), ("kn", "or"),
            ("or", "ta"), ("ta", "or"),
            ("or", "ml"), ("ml", "or"),
            ("or", "te"), ("te", "or"),
            ("ur", "or"), ("or", "ur"),
            ("ur", "ml"), ("ml", "ur"),
            ("ur", "kn"), ("kn", "ur"),
        }
        return (source, target) in weak_pairs

    def _translate_text(self, text: str, source: str, target: str) -> str:
        """
        Core translation using Google Translate via deep-translator.
        Falls back to pivot if direct translation fails.
        """
        if source == target:
            return text

        # Proactive English pivot for weak Indic pairs (per report)
        if self._needs_pivot(source, target):
            try:
                print(f"[Vaarta Translate] Proactive pivot via English for {source}->{target}")
                to_pivot = GoogleTranslator(source=source, target=PIVOT_LANGUAGE)
                pivot_text = to_pivot.translate(text)
                from_pivot = GoogleTranslator(source=PIVOT_LANGUAGE, target=target)
                return from_pivot.translate(pivot_text)
            except Exception as e:
                print(f"[Vaarta Translate] Proactive pivot failed, falling back to direct: {e}")

        try:
            # Direct translation (default path for most pairs)
            translator = GoogleTranslator(source=source, target=target)
            return translator.translate(text)
        except Exception as e:
            print(f"[Vaarta Translate] Direct translation failed: {e}")

            # Reactive pivot via English if direct fails
            if source != PIVOT_LANGUAGE and target != PIVOT_LANGUAGE:
                try:
                    print(f"[Vaarta Translate] Trying pivot via English...")
                    pivot_translator = GoogleTranslator(
                        source=source,
                        target=PIVOT_LANGUAGE
                    )
                    pivot_text = pivot_translator.translate(text)

                    final_translator = GoogleTranslator(
                        source=PIVOT_LANGUAGE,
                        target=target
                    )
                    return final_translator.translate(pivot_text)
                except Exception as e2:
                    print(f"[Vaarta Translate] Pivot also failed: {e2}")

            return text  # Return original if all translation fails

    # ------------------------------------------------------------------
    # Public Interface
    # ------------------------------------------------------------------

    def translate(
        self,
        text: str,
        source_language: str,
        target_language: str
    ) -> TranslationResult:
        """
        Main translation function.
        Handles personal vocab correction, code-switching, and translation.
        """
        source_name = SUPPORTED_LANGUAGES.get(source_language, source_language)
        target_name = SUPPORTED_LANGUAGES.get(target_language, target_language)
        used_pivot = False

        # Step 1: Apply personal vocabulary corrections
        corrected_text, corrections_applied = self._apply_personal_vocab(text)

        # Step 2: Identify English words to preserve (code-switching)
        preserved_words = self._extract_english_words(corrected_text)

        # Step 3: Protect English words with placeholders
        protected_text, placeholder_map = self._protect_english_words(
            corrected_text, preserved_words
        )

        # Step 4: Translate
        if source_language == target_language:
            translated = corrected_text
        else:
            # Check if pivot is needed
            if self._needs_pivot(source_language, target_language):
                used_pivot = True

            translated = self._translate_text(
                protected_text,
                source_language,
                target_language
            )

        # Step 5: Restore English words
        final_text = self._restore_english_words(translated, placeholder_map)

        return TranslationResult(
            original_text=text,
            translated_text=final_text,
            source_language=source_language,
            target_language=target_language,
            source_language_name=source_name,
            target_language_name=target_name,
            used_pivot=used_pivot,
            preserved_words=list(preserved_words),
            applied_corrections=corrections_applied
        )

    def get_supported_languages(self) -> dict:
        """Return all supported languages."""
        return SUPPORTED_LANGUAGES


# ------------------------------------------------------------------
# Quick Test
# ------------------------------------------------------------------
if __name__ == "__main__":
    translator = Translator()

    test_cases = [
        # (text, source, target)
        ("मेरा नाम शुभाशिष है और मुझे hospital जाना है।", "hi", "ta"),
        ("I need to go to the mall and buy shampoo.", "en", "hi"),
        ("నాకు doctor దగ్గరకి వెళ్ళాలి, bike తీసుకొస్తావా?", "te", "hi"),
        ("எனக்கு auto வேணும், signal கடந்து போகணும்.", "ta", "en"),
        ("Mujhe kal office jaana hai, laptop bhi leke jaaunga.", "hi", "en"),
    ]

    print("\n" + "="*60)
    print("VAARTA TRANSLATION TEST")
    print("="*60)

    for text, source, target in test_cases:
        result = translator.translate(text, source, target)
        print(f"\n[{result.source_language_name} → {result.target_language_name}]")
        print(f"  Original:    {result.original_text}")
        print(f"  Translated:  {result.translated_text}")
        if result.preserved_words:
            print(f"  Preserved:   {', '.join(result.preserved_words)}")
        if result.applied_corrections:
            print(f"  Corrections: {', '.join(result.applied_corrections)}")
        if result.used_pivot:
            print(f"  ℹ Used Hindi as pivot language")
        print("-"*60)