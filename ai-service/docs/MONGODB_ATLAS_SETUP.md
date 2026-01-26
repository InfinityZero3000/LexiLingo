# MongoDB Atlas Setup Guide for LexiLingo

> **Platform**: MongoDB Atlas (Cloud Database)  
> **Tier**: FREE (M0 - 512MB storage)  
> **Time Required**: ~10 minutes  
> **Purpose**: Production-ready database for Vercel deployment

---

##  Why MongoDB Atlas for LexiLingo?

### Vercel Deployment Requirements
```
┌─────────────────────────────────────────────────┐
│     Vercel Serverless Environment               │
├─────────────────────────────────────────────────┤
│   NO local database access                    │
│   NO persistent file storage                  │
│   Functions reset after each execution        │
│                                                 │
│   REQUIRES external cloud database:           │
│     • MongoDB Atlas                             │
│     • Other cloud DB services                   │
└─────────────────────────────────────────────────┘
```

### FREE Tier Benefits
- **512MB storage**: ~500,000 AI interactions
- **Unlimited bandwidth**: No data transfer fees
- **100 connections**: Sufficient for development/testing
- **Automatic backups**: Manual export available
- **Global availability**: 70+ regions
- **Zero maintenance**: Managed service

---

##  Step-by-Step Setup

### Step 1: Create MongoDB Atlas Account (2 minutes)

1. **Go to**: https://www.mongodb.com/cloud/atlas/register
2. **Sign up with**:
   - Email + password, OR
   - Google account (recommended)
3. **Verify email** if required

---

### Step 2: Create a FREE Cluster (3 minutes)

1. **After login**, click **"Create"** → **"Database"**

2. **Choose deployment type**:
   - Select: **M0 FREE**
   - Provider: AWS (or GCP/Azure)
   - Region: Choose closest to your Vercel region:
     ```
     Recommended regions for Vercel:
     • us-east-1 (US East - Virginia)      → Vercel: iad1
     • us-west-2 (US West - Oregon)        → Vercel: pdx1
     • eu-central-1 (Europe - Frankfurt)   → Vercel: fra1
     • ap-southeast-1 (Asia - Singapore)   → Vercel: sin1
     ```

3. **Cluster name**: `lexilingo-cluster` (or any name)

4. **Click**: **"Create Cluster"** (takes ~1-3 minutes)

---

### Step 3: Create Database User (1 minute)

1. **Go to**: **Security** → **Database Access**
2. **Click**: **"Add New Database User"**
3. **Authentication Method**: Password
4. **Username**: `lexilingo_user`
5. **Password**: Click **"Autogenerate Secure Password"** → **Copy it!**
   ```
   Example: ***REMOVED***
   Save this password securely!
   ```
6. **Database User Privileges**: 
   - Built-in Role: **"Read and write to any database"**
7. **Click**: **"Add User"**

---

### Step 4: Configure Network Access (1 minute)

1. **Go to**: **Security** → **Network Access**
2. **Click**: **"Add IP Address"**
3. **Choose one**:
   
   **Option A: Allow All (Easiest for development)**
   ```
   Click: "Allow Access from Anywhere"
   IP: 0.0.0.0/0
   ```
    Safe for free tier with strong password
   
   **Option B: Specific IPs (More secure)**
   ```
   Add your local IP
   Add Vercel IPs (if known)
   ```

4. **Click**: **"Confirm"**

---

### Step 5: Get Connection String (2 minutes)

1. **Go to**: **Deployment** → **Database**
2. **Click**: **"Connect"** button on your cluster
3. **Choose**: **"Connect your application"**
4. **Driver**: Python, Version: 3.12 or later
5. **Copy connection string**:
   ```
   ***REMOVED***
   ```

6. **Replace** `<password>` with your actual password:
   ```bash
   # Example (DON'T use this, use your own!)
   ***REMOVED***
   ```

---

### Step 6: Create Database and Collections (Manual - Optional)

You can skip this step as the Python client will auto-create collections. But if you want to do it manually:

1. **Go to**: **Collections** tab
2. **Click**: **"Create Database"**
   - Database name: `lexilingo_prod`
   - Collection name: `ai_interactions`
3. **Add more collections**:
   - `model_metrics`
   - `learning_patterns`
   - `training_queue`

---

##  Integration with LexiLingo

### For Local Development

**Update `.env` file** in `DL-Model-Support`:
```bash
# .env
MONGODB_ATLAS_URI=***REMOVED***
```

**Python client auto-detects**:
```python
# mongodb_client.py automatically chooses:
# - Local Docker if no MONGODB_ATLAS_URI env var
# - Atlas if MONGODB_ATLAS_URI is set
```

### For Vercel Deployment

1. **Go to Vercel Dashboard** → Your project → **Settings**
2. **Environment Variables** → **Add New**
   ```
   Name: MONGODB_ATLAS_URI
   Value: ***REMOVED***
   ```
3. **Redeploy** your Vercel app

---

##  Test Connection

### Method 1: Using Python Script

```bash
cd DL-Model-Support

# Set environment variable
export MONGODB_ATLAS_URI="***REMOVED***"

# Run test
python model/mongodb_client.py
```

**Expected output**:
```
 MongoDB client initialized (production environment)
 Connected to MongoDB: lexilingo_prod
 Logged interaction: 65a7f8b2c3d4e5f6g7h8i9j0
 Found 1 interactions
```

### Method 2: Using MongoDB Compass (GUI)

1. **Download**: https://www.mongodb.com/try/download/compass
2. **Open Compass**
3. **Paste** your connection string
4. **Click**: **Connect**
5. **Browse** your databases and collections

### Method 3: Using Mongo Shell

```bash
# Install mongosh
brew install mongosh  # macOS
# or download from: https://www.mongodb.com/try/download/shell

# Connect
mongosh "***REMOVED***"

# Test commands
> show dbs
> use lexilingo_prod
> db.ai_interactions.find().limit(5)
```

---

##  Monitor Your Database

### Atlas Dashboard Features

**Go to**: https://cloud.mongodb.com

1. **Metrics**:
   - Storage usage (X / 512 MB)
   - Connection count
   - Operations per second

2. **Performance Advisor**:
   - Slow query analysis
   - Index recommendations

3. **Real-time Performance**:
   - CPU usage
   - Network I/O
   - Active connections

4. **Alerts** (Setup recommended):
   - Storage > 80% full
   - Connection limit reached
   - Query performance degradation

---

##  Troubleshooting

### Error: "Authentication failed"
```bash
# Solution: Check username and password
# Make sure you replaced <password> in connection string
# Password is case-sensitive!
```

### Error: "Connection timeout"
```bash
# Solution: Check Network Access
# - Add 0.0.0.0/0 to IP whitelist
# - Wait 2-3 minutes after adding IP
```

### Error: "Too many connections"
```bash
# Solution: FREE tier limit is 100 connections
# - Close unused connections
# - Use connection pooling (already configured in mongodb_client.py)
```

### Error: "Storage limit exceeded"
```bash
# Solution: FREE tier is 512MB
# - Check TTL indexes are working (auto-delete old data)
# - Manually delete old test data
# - Consider upgrading to M2 ($9/month) if needed
```

---

##  Pricing Information

### FREE Tier (M0) - Current Setup
```yaml
Storage: 512 MB
RAM: Shared
vCPU: Shared
Connections: 100 concurrent
Price: $0 / month FOREVER
```

### Upgrade Path (When Needed)

**M2 Cluster** - $9/month
```yaml
Storage: 2 GB
RAM: 2 GB
vCPU: 2 shared
Connections: 500
Backups: Automated
```

**M5 Cluster** - $25/month
```yaml
Storage: 5 GB
RAM: 8 GB
vCPU: 2 dedicated
Connections: 1500
Backups: Automated + Point-in-time restore
```

**When to upgrade?**
- Storage > 512MB (check dashboard)
- Need automated backups
- >100 concurrent users
- Production app with paying customers

---

##  Security Best Practices

### 1. Environment Variables
```bash
#  GOOD: Use environment variables
export MONGODB_ATLAS_URI="***REMOVED***"
```

### 2. Connection String Security
```bash
# Never commit .env files to git!
echo ".env" >> .gitignore

# Use different passwords for dev/prod
MONGODB_ATLAS_URI_DEV=...
MONGODB_ATLAS_URI_PROD=...
```

### 3. Regular Password Rotation
- Change database password every 3-6 months
- Update in Atlas Dashboard → Database Access
- Update in Vercel environment variables

### 4. IP Whitelist (Production)
```
For production, whitelist specific IPs:
- Your office IP
- Vercel deployment IPs
- CI/CD runner IPs
Remove 0.0.0.0/0 from whitelist
```

---

##  Useful Resources

- **MongoDB Atlas Docs**: https://www.mongodb.com/docs/atlas/
- **Python Driver (PyMongo)**: https://pymongo.readthedocs.io/
- **Connection String Format**: https://www.mongodb.com/docs/manual/reference/connection-string/
- **FREE Tier Limits**: https://www.mongodb.com/pricing
- **Vercel Integration**: https://vercel.com/integrations/mongodbatlas

---

##  Next Steps

After setup is complete:

1. **Test local development**:
   ```bash
   cd DL-Model-Support
   export MONGODB_ATLAS_URI="your_connection_string"
   python model/mongodb_client.py
   ```

2. **Add to Vercel**:
   - Set environment variable in Vercel dashboard
   - Redeploy

3. **Start logging AI interactions**:
   - MongoDB client is ready to use
   - Integrate with Orchestrator (Phase 3)

4. **Monitor regularly**:
   - Check Atlas dashboard weekly
   - Set up alerts for storage/connections
   - Review slow queries

---

> **Support**: If you encounter issues, check MongoDB Community Forums:  
> https://www.mongodb.com/community/forums/

> **LexiLingo Team**: For project-specific questions, contact the team.
