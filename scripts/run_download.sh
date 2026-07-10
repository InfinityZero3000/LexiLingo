#!/bin/bash
cd /opt/lexilingo/scripts
nohup python3 download_oxford_audio.py > /tmp/oxford_download.log 2>&1 &
echo $!
