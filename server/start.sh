#!/bin/bash
set -e

echo "==================================================="
echo "   MusicCloud Server Setup (Ubuntu / Debian / Linux)"
echo "==================================================="

# 1. Update and install dependencies
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv

# 2. Setup Virtual Environment
if [ ! -d "venv" ]; then
    echo "Creating python virtual environment..."
    python3 -m venv venv
fi

# 3. Install requirements
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo ""
echo "Setup complete! Starting server..."
python3 main.py
