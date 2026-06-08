from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
import io
import soundfile as sf
from kokoro import KPipeline

app = FastAPI()

# Initialize the Kokoro pipeline (it will download weights on first run, ~300MB)
print("[TTS Server] Initializing Kokoro Pipeline...")
try:
    pipeline = KPipeline(lang_code='a')
    print("[TTS Server] Kokoro Pipeline initialized successfully.")
except Exception as e:
    print("[TTS Server] Error initializing pipeline: ", e)
    pipeline = None

@app.get("/health")
async def health_check():
    return {"status": "ok", "pipeline_ready": pipeline is not None}

@app.post("/tts")
async def text_to_speech(data: dict):
    if pipeline is None:
        raise HTTPException(status_code=500, detail="Kokoro pipeline not initialized")
        
    text = data.get("text", "")
    voice = data.get("voice", "af_bella")
    speed = data.get("speed", 1.0)
    
    if not text:
        raise HTTPException(status_code=400, detail="Text cannot be empty")
        
    print(f"[TTS Server] Generating speech for text: '{text}' using voice: '{voice}'")
    try:
        generator = pipeline(text, voice=voice, speed=speed, split_pattern=r'\n+')
        for _, _, audio in generator:
            wav_io = io.BytesIO()
            # Kokoro sample rate is 24000Hz
            sf.write(wav_io, audio, 24000, format='WAV', subtype='PCM_16')
            wav_io.seek(0)
            return Response(content=wav_io.read(), media_type="audio/wav")
    except Exception as e:
        print("[TTS Server] Error during generation: ", e)
        raise HTTPException(status_code=500, detail=str(e))
        
    raise HTTPException(status_code=500, detail="Failed to generate audio")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5000)
