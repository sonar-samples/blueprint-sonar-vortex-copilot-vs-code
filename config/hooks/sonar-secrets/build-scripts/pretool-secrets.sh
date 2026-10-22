#!/bin/bash
if ! command -v sonar &> /dev/null; then
  exit 0
fi
sonar hook copilot-pre-tool-use
