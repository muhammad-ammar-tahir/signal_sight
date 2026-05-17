@echo off
:: SignalSight Backend Startup Script (Windows)
:: Installs dependencies and starts the FastAPI server.

echo [SignalSight] Installing Python dependencies...
pip install -r requirements.txt --quiet

echo.
echo [SignalSight] Starting FastAPI server on http://0.0.0.0:8000
echo    API docs  : http://127.0.0.1:8000/docs
echo    WebSocket : ws://127.0.0.1:8000/ws
echo.
echo Press Ctrl+C to stop.
echo.

uvicorn main:app --host 0.0.0.0 --port 8000 --reload --log-level info
