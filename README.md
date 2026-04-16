# VAARTA

**Real-Time Multilingual Voice Translation System**
*by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi*

---

## What is Vaarta?

Vaarta is a real-time voice translation system for India's public infrastructure. Two people who don't share a language open one app, place a phone between them, speak naturally, and understand each other instantly.

**No buttons. No setup. No manual language selection.** The app disappears. The conversation remains.

### Target Environments
Hospitals, police stations, public transport, government offices.

### Target Users
Migrants, patients, tourists, non-local citizens — people who need translation most.

---

## Supported Languages

Hindi, Bengali, Marathi, Telugu, Tamil, Gujarati, Urdu, Kannada, Odia, Malayalam, English.

**110 bidirectional translation pairs** with Hindi as pivot fallback.

---

## Architecture

```
Microphone Input
       ↓
  stt.py — transcribe audio, detect language, detect gender
       ↓
  clarify.py — check confidence, domain keywords, surface clarification
       ↓
  translate.py — apply personal vocab, preserve English words, translate
       ↓
  tts.py — generate speech with gender-matched voice
       ↓
  Speaker hears translated output
```

### Technology Stack

| Component | Technology |
|-----------|-----------|
| Backend | Python 3.13, FastAPI + Uvicorn |
| Speech-to-Text | faster-whisper (small, CPU, int8) |
| Translation | deep-translator (Google) |
| Text-to-Speech | ElevenLabs (eleven_multilingual_v2) + gTTS fallback |
| Gender Detection | librosa pitch analysis (165 Hz threshold) |
| Frontend | Flutter (Android) |
| Real-time | WebSocket |

---

## Setup

### Backend

```bash
cd vaarta
python -m venv .venv
.venv\Scripts\activate       # Windows
pip install -r requirements.txt
```

Create `backend/.env`:
```
ELEVENLABS_API_KEY=your_key_here
```

Start the server:
```bash
cd backend
python main.py
```

Server runs at `http://0.0.0.0:8000`.

### Frontend

```bash
cd frontend
flutter pub get
flutter run
```

On the connection screen, enter your server's IP address (e.g., `192.168.1.x:8000`).

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/languages` | Supported languages list |
| GET | `/vocabulary` | Personal vocabulary corrections |
| DELETE | `/vocabulary/{word}` | Remove a saved correction |
| WS | `/ws/session` | Real-time audio translation session |

---

## Key Features

- **Always-on listening** — opens and listens immediately
- **Automatic language detection** — powered by Whisper
- **Code-switching** — preserves English words in Indian language speech
- **Gender-matched voice** — detects pitch, plays matching male/female voice
- **Domain vocabulary packs** — Medical and Transport for high-stakes accuracy
- **Proactive clarification** — flags low-confidence transcriptions
- **Self-learning vocabulary** — corrections saved and applied automatically
- **Replay** — one tap replays the last translation

---

## Project Structure

```
vaarta/
├── requirements.txt
├── README.md
├── backend/
│   ├── .env
│   ├── .gitignore
│   ├── stt.py              # Speech-to-Text engine
│   ├── Translate.py         # Translation with code-switching
│   ├── tts.py              # Text-to-Speech engine
│   ├── clarify.py          # Proactive clarification
│   ├── main.py             # FastAPI server
│   └── vocabulary/
│       ├── personal.json   # User corrections
│       ├── medical.json    # Medical domain vocabulary
│       └── transport.json  # Transport domain vocabulary
└── frontend/
    └── lib/
        ├── main.dart
        ├── screens/
        │   ├── home_screen.dart
        │   └── settings_screen.dart
        ├── widgets/
        │   ├── waveform.dart
        │   ├── transcript_bubble.dart
        │   ├── clarify_prompt.dart
        │   └── replay_button.dart
        └── services/
            ├── websocket_service.dart
            └── audio_service.dart
```

---

*Vaarta by Adrelia | CIIC, Christ University Delhi NCR*
