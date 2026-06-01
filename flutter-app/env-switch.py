import sys
import shutil
import os

def switch(env_type):
    # Determine paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    if env_type in ['dev', 'development']:
        src = os.path.join(script_dir, '.env.development')
        dest = os.path.join(script_dir, '.env')
        print(f"Switching to DEVELOPMENT environment...")
    elif env_type in ['prod', 'production']:
        src = os.path.join(script_dir, '.env.production')
        dest = os.path.join(script_dir, '.env')
        print(f"Switching to PRODUCTION environment...")
    else:
        print("Invalid environment type! Use 'dev' or 'prod'.")
        sys.exit(1)
        
    if not os.path.exists(src):
        print(f"Error: Source file {src} does not exist!")
        sys.exit(1)
        
    try:
        shutil.copyfile(src, dest)
        print(f"Successfully copied {src} to {dest}")
    except Exception as e:
        print(f"Error copying file: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 env-switch.py [dev|prod]")
        sys.exit(1)
    switch(sys.argv[1])
