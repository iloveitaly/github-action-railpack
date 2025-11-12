#!/bin/bash

echo "Hello World from RailPack!"
echo "Current date: $(date)"
echo "Container running successfully!"

# Keep the process running
while true; do
  echo "Heartbeat: $(date)"
  sleep 60
done
