#!/usr/bin/env python3
"""
Interactive TTS/STT Console Tool for LexiLingo
Công cụ kiểm tra TTS và STT với giao diện console tương tác
"""

import os
import sys
import wave
from pathlib import Path
from datetime import datetime

# Change to backend directory
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Global variables for models (lazy load)
tts_voice = None
stt_model = None


def print_header():
    """Print application header"""
    print("\n" + "=" * 70)
    print("  🎤 LexiLingo - TTS/STT Console Tool")
    print("  Text-to-Speech & Speech-to-Text Testing Interface")
    print("=" * 70)


def print_menu():
    """Print main menu"""
    print("\n📋 MENU - Chọn chức năng:")
    print("  1. 🔊 TTS - Text to Speech (Chuyển text thành giọng nói)")
    print("  2. 🎙️  STT - Speech to Text (Chuyển giọng nói thành text)")
    print("  3. 🔄 Round-trip Test (TTS → STT)")
    print("  4. ℹ️  System Info (Thông tin hệ thống)")
    print("  5. ❌ Exit (Thoát)")
    print("-" * 70)


def load_tts_model():
    """Load TTS (Piper) model"""
    global tts_voice
    
    if tts_voice is not None:
        return tts_voice
    
    try:
        print("🔄 Loading TTS model (Piper)...")
        from piper import PiperVoice
        
        model_path = "./models/piper/en_US-lessac-medium.onnx"
        config_path = "./models/piper/en_US-lessac-medium.onnx.json"
        
        if not os.path.exists(model_path):
            print(f"❌ Error: TTS model not found at {model_path}")
            return None
        
        tts_voice = PiperVoice.load(model_path, config_path=config_path)
        print("✅ TTS model loaded successfully")
        return tts_voice
        
    except Exception as e:
        print(f"❌ Error loading TTS model: {e}")
        return None


def load_stt_model():
    """Load STT (Faster-Whisper) model"""
    global stt_model
    
    if stt_model is not None:
        return stt_model
    
    try:
        print("🔄 Loading STT model (Faster-Whisper large-v3)...")
        print("⚠️  This may take 20-30 seconds on first load...")
        from faster_whisper import WhisperModel
        
        stt_model = WhisperModel("large-v3", device="cpu", compute_type="int8")
        print("✅ STT model loaded successfully")
        return stt_model
        
    except Exception as e:
        print(f"❌ Error loading STT model: {e}")
        return None


def text_to_speech():
    """Convert text to speech"""
    print("\n" + "=" * 70)
    print("  🔊 TEXT TO SPEECH (TTS)")
    print("=" * 70)
    
    # Load model
    voice = load_tts_model()
    if voice is None:
        return
    
    # Get input text
    print("\n📝 Nhập text bạn muốn chuyển thành giọng nói:")
    print("   (Nhấn Enter để dùng text mẫu)")
    text = input("   > ").strip()
    
    if not text:
        text = "Hello! This is LexiLingo. I can convert your text into natural speech."
        print(f"   Using sample text: \"{text}\"")
    
    # Generate output filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"./output_tts_{timestamp}.wav"
    
    try:
        print(f"\n🔄 Synthesizing speech...")
        
        # Collect audio chunks
        audio_data = b''
        sample_rate = None
        sample_channels = None
        sample_width = None
        
        for audio_chunk in voice.synthesize(text):
            audio_data += audio_chunk.audio_int16_bytes
            if sample_rate is None:
                sample_rate = audio_chunk.sample_rate
                sample_channels = audio_chunk.sample_channels
                sample_width = audio_chunk.sample_width
        
        if not audio_data:
            print("❌ No audio data generated")
            return
        
        # Save to WAV file
        with wave.open(output_file, "wb") as wav_file:
            wav_file.setnchannels(sample_channels)
            wav_file.setsampwidth(sample_width)
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(audio_data)
        
        # Display results
        size_kb = len(audio_data) / 1024
        duration = len(audio_data) / (sample_rate * sample_channels * sample_width)
        
        print("\n✅ SUCCESS - Audio generated!")
        print(f"   📁 File: {output_file}")
        print(f"   📊 Size: {size_kb:.2f} KB")
        print(f"   ⏱️  Duration: {duration:.2f} seconds")
        print(f"   🎵 Sample rate: {sample_rate} Hz")
        print(f"   🔊 Channels: {sample_channels}")
        print(f"\n   💡 Tip: Mở file {output_file} để nghe audio")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()


def speech_to_text():
    """Convert speech to text"""
    print("\n" + "=" * 70)
    print("  🎙️  SPEECH TO TEXT (STT)")
    print("=" * 70)
    
    # Load model
    model = load_stt_model()
    if model is None:
        return
    
    # Get input audio file
    print("\n📁 Nhập đường dẫn file audio (WAV):")
    print("   (Nhấn Enter để dùng file TTS output gần nhất)")
    audio_file = input("   > ").strip()
    
    if not audio_file:
        # Find latest TTS output
        tts_files = sorted(Path(".").glob("output_tts_*.wav"), key=lambda x: x.stat().st_mtime, reverse=True)
        if tts_files:
            audio_file = str(tts_files[0])
            print(f"   Using latest TTS output: {audio_file}")
        else:
            print("❌ No TTS output files found. Please provide a file path.")
            return
    
    if not os.path.exists(audio_file):
        print(f"❌ File not found: {audio_file}")
        return
    
    try:
        print(f"\n🔄 Transcribing audio...")
        
        # Transcribe
        segments, info = model.transcribe(
            audio_file,
            beam_size=5,
            language=None,  # Auto-detect
            vad_filter=True
        )
        
        # Collect text
        text = ""
        for segment in segments:
            text += segment.text
        
        text = text.strip()
        
        # Display results
        print("\n✅ SUCCESS - Transcription completed!")
        print(f"   🌍 Detected language: {info.language}")
        print(f"   📝 Transcribed text:")
        print(f"\n   \"{text}\"")
        
        # Save to file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = f"./output_stt_{timestamp}.txt"
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(f"Language: {info.language}\n")
            f.write(f"Text: {text}\n")
        
        print(f"\n   💾 Saved to: {output_file}")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()


def round_trip_test():
    """Test TTS -> STT round trip"""
    print("\n" + "=" * 70)
    print("  🔄 ROUND-TRIP TEST (TTS → STT)")
    print("=" * 70)
    
    # Load models
    print("\n🔄 Loading models...")
    voice = load_tts_model()
    model = load_stt_model()
    
    if voice is None or model is None:
        return
    
    # Get input text
    print("\n📝 Nhập text để test round-trip:")
    print("   (Nhấn Enter để dùng text mẫu)")
    original_text = input("   > ").strip()
    
    if not original_text:
        original_text = "The quick brown fox jumps over the lazy dog"
        print(f"   Using sample: \"{original_text}\"")
    
    try:
        # Step 1: TTS
        print(f"\n📝 Original text: \"{original_text}\"")
        print("🔄 Step 1: Converting text to speech...")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        temp_audio = f"./output_roundtrip_{timestamp}.wav"
        
        # Generate audio
        audio_data = b''
        sample_rate = None
        sample_channels = None
        sample_width = None
        
        for audio_chunk in voice.synthesize(original_text):
            audio_data += audio_chunk.audio_int16_bytes
            if sample_rate is None:
                sample_rate = audio_chunk.sample_rate
                sample_channels = audio_chunk.sample_channels
                sample_width = audio_chunk.sample_width
        
        # Save audio
        with wave.open(temp_audio, "wb") as wav_file:
            wav_file.setnchannels(sample_channels)
            wav_file.setsampwidth(sample_width)
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(audio_data)
        
        print(f"   ✅ Audio generated: {temp_audio}")
        
        # Step 2: STT
        print("🔄 Step 2: Converting speech back to text...")
        
        segments, info = model.transcribe(
            temp_audio,
            beam_size=5,
            language="en",
            vad_filter=True
        )
        
        transcribed_text = "".join(segment.text for segment in segments).strip()
        
        # Compare
        print(f"\n📊 RESULTS:")
        print(f"   Original:    \"{original_text}\"")
        print(f"   Transcribed: \"{transcribed_text}\"")
        
        # Calculate accuracy
        original_words = set(original_text.lower().split())
        transcribed_words = set(transcribed_text.lower().split())
        common_words = original_words.intersection(transcribed_words)
        
        if len(original_words) > 0:
            accuracy = len(common_words) / len(original_words) * 100
            print(f"\n   🎯 Accuracy: {accuracy:.1f}%")
            print(f"   ✓ Matched words: {len(common_words)}/{len(original_words)}")
            
            if accuracy >= 70:
                print("   ✅ PASSED - Good accuracy!")
            else:
                print("   ⚠️  Low accuracy - consider checking audio quality")
        
        print(f"\n   💾 Audio saved: {temp_audio}")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()


def show_system_info():
    """Show system information"""
    print("\n" + "=" * 70)
    print("  ℹ️  SYSTEM INFORMATION")
    print("=" * 70)
    
    # Check models
    print("\n📦 MODELS:")
    
    # TTS
    tts_model = "./models/piper/en_US-lessac-medium.onnx"
    tts_config = "./models/piper/en_US-lessac-medium.onnx.json"
    
    if os.path.exists(tts_model):
        size = os.path.getsize(tts_model) / (1024 * 1024)
        print(f"   ✅ TTS (Piper): {size:.2f} MB")
    else:
        print(f"   ❌ TTS (Piper): Not found")
    
    # STT
    stt_model_dir = "./models/whisper/models--Systran--faster-whisper-large-v3"
    if os.path.exists(stt_model_dir):
        print(f"   ✅ STT (Whisper large-v3): Installed")
    else:
        print(f"   ❌ STT (Whisper large-v3): Not found")
    
    # Dependencies
    print("\n📚 DEPENDENCIES:")
    
    deps = ["piper", "faster_whisper", "numpy", "wave"]
    for dep in deps:
        try:
            if dep == "wave":
                import wave
                print(f"   ✅ {dep}: Built-in")
            else:
                module = __import__(dep)
                version = getattr(module, "__version__", "unknown")
                print(f"   ✅ {dep}: v{version}")
        except ImportError:
            print(f"   ❌ {dep}: Not installed")
    
    # Output files
    print("\n📁 OUTPUT FILES:")
    tts_files = list(Path(".").glob("output_tts_*.wav"))
    stt_files = list(Path(".").glob("output_stt_*.txt"))
    roundtrip_files = list(Path(".").glob("output_roundtrip_*.wav"))
    
    print(f"   TTS outputs: {len(tts_files)} files")
    print(f"   STT outputs: {len(stt_files)} files")
    print(f"   Round-trip outputs: {len(roundtrip_files)} files")
    
    if tts_files or stt_files or roundtrip_files:
        print("\n   💡 Tip: Use 'rm output_*.wav output_*.txt' to clean up")


def main():
    """Main application loop"""
    print_header()
    
    while True:
        print_menu()
        
        try:
            choice = input("Chọn chức năng (1-5): ").strip()
            
            if choice == "1":
                text_to_speech()
            elif choice == "2":
                speech_to_text()
            elif choice == "3":
                round_trip_test()
            elif choice == "4":
                show_system_info()
            elif choice == "5":
                print("\n Goodbye! Đã thoát chương trình.")
                break
            else:
                print("❌ Lựa chọn không hợp lệ. Vui lòng chọn 1-5.")
                
        except KeyboardInterrupt:
            print("\n\n Goodbye! Đã thoát chương trình.")
            break
        except Exception as e:
            print(f"\n❌ Unexpected error: {e}")
            import traceback
            traceback.print_exc()


if __name__ == "__main__":
    main()
