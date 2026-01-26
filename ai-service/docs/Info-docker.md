1. **Test MongoDB setup:**
   ```bash
   cd LexiLingo_backend
   docker-compose up -d
   ```

2. **Verify collections created:**
   - Open Mongo Express: http://localhost:8081
   - Login: admin / admin123
   - Check `lexilingo` database has 6 collections

3. **Test API with MongoDB:**
   ```bash
   # Should return healthy status
   curl http://localhost:8000/health
   ```

4. **Connect DL models:**
   - Create API in DL-Model-Support to expose Qwen models
   - Backend will call DL API for grammar analysis
   - DL models can access MongoDB for training data