import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "SignalSight WiFi Intelligence"
    JWT_SECRET: str = "signalsight-dev-secret-change-me"
    ADMIN_PASSWORD: str = "changeme"
    DATABASE_URL: str = "sqlite:///./signalsight.db"
    LOG_LEVEL: str = "INFO"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()
