#!/usr/bin/env python3
"""
Model Verification Script for LexiLingo Backend

Checks if all required AI models are downloaded correctly and completely.
"""

import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple


class ModelVerifier:
    """Verify downloaded AI models"""
    
    def __init__(self, models_dir: str = "./models"):
        self.models_dir = Path(models_dir)
        self.results = {}
        
    def check_file_exists(self, path: Path, min_size_mb: float = 0) -> Tuple[bool, str]:
        """Check if file exists and meets minimum size requirement"""
        if not path.exists():
            return False, f"File not found: {path}"
        
        size_mb = path.stat().st_size / (1024 * 1024)
        if size_mb < min_size_mb:
            return False, f"File too small: {size_mb:.2f}MB < {min_size_mb}MB"
        
        return True, f"OK ({size_mb:.2f}MB)"
    
    def verify_whisper(self) -> Dict:
        """Verify Whisper large-v3 model"""
        print("\n" + "="*60)
        print("🔍 Checking Whisper large-v3 (STT)")
        print("="*60)
        
        whisper_dir = self.models_dir / "whisper" / "models--Systran--faster-whisper-large-v3"
        
        if not whisper_dir.exists():
            print("❌ Whisper model directory not found")
            return {"status": "missing", "size_gb": 0, "files": []}
        
        # Check for snapshot directory
        snapshots = list(whisper_dir.glob("snapshots/*"))
        if not snapshots:
            print("❌ No snapshot found")
            return {"status": "incomplete", "size_gb": 0, "files": []}
        
        snapshot = snapshots[0]
        required_files = [
            ("config.json", 0),  # Small JSON file
            ("preprocessor_config.json", 0),  # Small JSON file
            ("tokenizer.json", 0.1),
            ("vocabulary.json", 0.4),
        ]
        
        files_ok = []
        files_missing = []
        
        for filename, min_size in required_files:
            file_path = snapshot / filename
            ok, msg = self.check_file_exists(file_path, min_size)
            if ok:
                print(f"  ✅ {filename}: {msg}")
                files_ok.append(filename)
            else:
                print(f"  ❌ {filename}: {msg}")
                files_missing.append(filename)
        
        # Check for binary blobs
        blobs_dir = whisper_dir / "blobs"
        if blobs_dir.exists():
            blob_count = len(list(blobs_dir.iterdir()))
            total_blob_size = sum(f.stat().st_size for f in blobs_dir.iterdir()) / (1024**3)
            print(f"  ✅ Model weights: {blob_count} blobs ({total_blob_size:.2f}GB)")
        else:
            print(f"  ❌ Model weights: No blobs directory")
            files_missing.append("blobs")
        
        # Calculate total size
        total_size = sum(f.stat().st_size for f in whisper_dir.rglob('*') if f.is_file()) / (1024**3)
        
        status = "complete" if not files_missing else "incomplete"
        print(f"\nTotal size: {total_size:.2f}GB")
        print(f"Status: {'✅ Complete' if status == 'complete' else '❌ Incomplete'}")
        
        return {
            "status": status,
            "size_gb": total_size,
            "files_ok": files_ok,
            "files_missing": files_missing
        }
    
    def verify_embeddings(self) -> Dict:
        """Verify Sentence-Transformers embeddings"""
        print("\n" + "="*60)
        print("🔍 Checking Sentence-Transformers (Embeddings)")
        print("="*60)
        
        emb_dir = self.models_dir / "embeddings" / "models--sentence-transformers--all-MiniLM-L6-v2"
        
        if not emb_dir.exists():
            print("❌ Embeddings model directory not found")
            return {"status": "missing", "size_mb": 0, "files": []}
        
        # Check for snapshot
        snapshots = list(emb_dir.glob("snapshots/*"))
        if not snapshots:
            print("❌ No snapshot found")
            return {"status": "incomplete", "size_mb": 0, "files": []}
        
        snapshot = snapshots[0]
        required_files = [
            ("config.json", 0),  # Small JSON file
            ("tokenizer.json", 0.3),
            ("vocab.txt", 0.2),
            ("model.safetensors", 80),  # ~90MB
        ]
        
        files_ok = []
        files_missing = []
        
        for filename, min_size in required_files:
            file_path = snapshot / filename
            ok, msg = self.check_file_exists(file_path, min_size)
            if ok:
                print(f"  ✅ {filename}: {msg}")
                files_ok.append(filename)
            else:
                print(f"  ❌ {filename}: {msg}")
                files_missing.append(filename)
        
        # Calculate total size
        total_size = sum(f.stat().st_size for f in emb_dir.rglob('*') if f.is_file()) / (1024**2)
        
        status = "complete" if not files_missing else "incomplete"
        print(f"\nTotal size: {total_size:.2f}MB")
        print(f"Status: {'✅ Complete' if status == 'complete' else '❌ Incomplete'}")
        
        return {
            "status": status,
            "size_mb": total_size,
            "files_ok": files_ok,
            "files_missing": files_missing
        }
    
    def verify_hubert(self) -> Dict:
        """Verify HuBERT pronunciation model"""
        print("\n" + "="*60)
        print("🔍 Checking HuBERT large-ls960-ft (Pronunciation)")
        print("="*60)
        
        hubert_dir = self.models_dir / "hubert" / "models--facebook--hubert-large-ls960-ft"
        
        if not hubert_dir.exists():
            print("❌ HuBERT model directory not found")
            return {"status": "missing", "size_gb": 0, "files": []}
        
        # Check for snapshots
        snapshots = list(hubert_dir.glob("snapshots/*"))
        if not snapshots:
            print("❌ No snapshot found")
            return {"status": "incomplete", "size_gb": 0, "files": []}
        
        # Check all snapshots for safetensors (preferred) or pytorch_model.bin
        safetensors_found = False
        pytorch_found = False
        
        for snapshot in snapshots:
            safetensors = snapshot / "model.safetensors"
            pytorch = snapshot / "pytorch_model.bin"
            
            if safetensors.exists():
                size_mb = safetensors.stat().st_size / (1024**2)
                print(f"  ✅ model.safetensors: {size_mb:.2f}MB (SECURE)")
                safetensors_found = True
            
            if pytorch.exists():
                size_mb = pytorch.stat().st_size / (1024**2)
                print(f"  ⚠️  pytorch_model.bin: {size_mb:.2f}MB (INSECURE - can delete)")
                pytorch_found = True
            
            # Check config files
            config = snapshot / "config.json"
            if config.exists():
                print(f"  ✅ config.json: OK")
            
            vocab = snapshot / "vocab.json"
            if vocab.exists():
                print(f"  ✅ vocab.json: OK")
        
        # Calculate total size
        total_size = sum(f.stat().st_size for f in hubert_dir.rglob('*') if f.is_file()) / (1024**3)
        
        if safetensors_found:
            status = "complete"
            print(f"\n✅ Safetensors format available - READY TO USE")
        elif pytorch_found:
            status = "insecure"
            print(f"\n⚠️  Only PyTorch format found - SECURITY RISK")
        else:
            status = "incomplete"
            print(f"\n❌ No model weights found")
        
        if pytorch_found and safetensors_found:
            print(f"💡 Tip: Delete pytorch_model.bin to save ~1.2GB")
        
        print(f"\nTotal size: {total_size:.2f}GB")
        
        return {
            "status": status,
            "size_gb": total_size,
            "has_safetensors": safetensors_found,
            "has_pytorch": pytorch_found
        }
    
    def verify_piper(self) -> Dict:
        """Verify Piper TTS voice files"""
        print("\n" + "="*60)
        print("🔍 Checking Piper TTS (Text-to-Speech)")
        print("="*60)
        
        piper_dir = self.models_dir / "piper"
        
        if not piper_dir.exists():
            print("❌ Piper directory not found")
            return {"status": "missing", "size_mb": 0, "files": []}
        
        required_files = [
            ("en_US-lessac-medium.onnx", 50),  # ~63MB
            ("en_US-lessac-medium.onnx.json", 0),  # Small JSON file
        ]
        
        files_ok = []
        files_missing = []
        
        for filename, min_size in required_files:
            file_path = piper_dir / filename
            ok, msg = self.check_file_exists(file_path, min_size)
            if ok:
                print(f"  ✅ {filename}: {msg}")
                files_ok.append(filename)
            else:
                print(f"  ❌ {filename}: {msg}")
                files_missing.append(filename)
        
        # Calculate total size
        if piper_dir.exists():
            total_size = sum(f.stat().st_size for f in piper_dir.rglob('*') if f.is_file()) / (1024**2)
        else:
            total_size = 0
        
        status = "complete" if not files_missing else "missing"
        print(f"\nTotal size: {total_size:.2f}MB")
        print(f"Status: {'✅ Complete' if status == 'complete' else '❌ Missing/Incomplete'}")
        
        return {
            "status": status,
            "size_mb": total_size,
            "files_ok": files_ok,
            "files_missing": files_missing
        }
    
    def run_verification(self):
        """Run complete verification"""
        print("\n" + "="*70)
        print("🔍 LEXILINGO MODEL VERIFICATION SCRIPT")
        print("="*70)
        print(f"📂 Models directory: {self.models_dir.absolute()}")
        
        # Verify each model
        self.results['whisper'] = self.verify_whisper()
        self.results['embeddings'] = self.verify_embeddings()
        self.results['hubert'] = self.verify_hubert()
        self.results['piper'] = self.verify_piper()
        
        # Summary
        print("\n" + "="*70)
        print("VERIFICATION SUMMARY")
        print("="*70)
        
        total_size_gb = 0
        complete_count = 0
        total_models = 4
        
        # Whisper
        w = self.results['whisper']
        if w['status'] == 'complete':
            print(f"✅ Whisper large-v3: {w['size_gb']:.2f}GB - READY")
            complete_count += 1
        else:
            print(f"❌ Whisper large-v3: {w['status'].upper()}")
        total_size_gb += w.get('size_gb', 0)
        
        # Embeddings
        e = self.results['embeddings']
        if e['status'] == 'complete':
            print(f"✅ Embeddings: {e['size_mb']:.2f}MB - READY")
            complete_count += 1
        else:
            print(f"❌ Embeddings: {e['status'].upper()}")
        total_size_gb += e.get('size_mb', 0) / 1024
        
        # HuBERT
        h = self.results['hubert']
        if h['status'] == 'complete':
            print(f"✅ HuBERT: {h['size_gb']:.2f}GB - READY")
            complete_count += 1
        elif h['status'] == 'insecure':
            print(f"⚠️  HuBERT: {h['size_gb']:.2f}GB - INSECURE (use safetensors)")
            complete_count += 0.5
        else:
            print(f"❌ HuBERT: {h['status'].upper()}")
        total_size_gb += h.get('size_gb', 0)
        
        # Piper
        p = self.results['piper']
        if p['status'] == 'complete':
            print(f"✅ Piper TTS: {p['size_mb']:.2f}MB - READY")
            complete_count += 1
        else:
            print(f"❌ Piper TTS: {p['status'].upper()}")
        total_size_gb += p.get('size_mb', 0) / 1024
        
        print("\n" + "-"*70)
        print(f"Total disk usage: {total_size_gb:.2f}GB")
        print(f"Models ready: {complete_count}/{total_models} ({complete_count/total_models*100:.0f}%)")
        
        # Recommendations
        print("\n" + "="*70)
        print("💡 RECOMMENDATIONS")
        print("="*70)
        
        if self.results['whisper']['status'] != 'complete':
            print("❗ Run: ./download.sh  # To download Whisper large-v3")
        
        if self.results['embeddings']['status'] != 'complete':
            print("❗ Run: ./download.sh  # To download embeddings")
        
        if self.results['hubert']['status'] == 'insecure':
            print("💡 HuBERT pytorch_model.bin can be deleted (use safetensors)")
            print("   rm -f models/hubert/*/snapshots/*/pytorch_model.bin")
        
        if self.results['piper']['status'] != 'complete':
            print("❗ Run: ./download.sh  # To download Piper TTS")
        
        if complete_count == total_models:
            print("\n🎉 All models are complete and ready to use!")
        
        print("\n" + "="*70)
        
        # Return exit code
        return 0 if complete_count >= 3 else 1


def main():
    """Main entry point"""
    # Change to backend directory if running from scripts/
    if Path.cwd().name == 'scripts':
        os.chdir('..')
    
    verifier = ModelVerifier()
    exit_code = verifier.run_verification()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
