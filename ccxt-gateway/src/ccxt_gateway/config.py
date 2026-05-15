"""Configuration management for ccxt-gateway."""

import os
from typing import Any, Dict, Optional

import yaml
from pydantic import Field
from pydantic_settings import BaseSettings


class ServerConfig(BaseSettings):
    """Server configuration."""

    model_config = {"env_prefix": "CCXT_GATEWAY_SERVER_"}

    host: str = "0.0.0.0"
    port: int = 8999
    debug: bool = False
    use_ssl: bool = False
    ssl_cert: Optional[str] = None
    ssl_key: Optional[str] = None
    use_granian: bool = False


class ZMQConfig(BaseSettings):
    """ZeroMQ configuration."""

    model_config = {"env_prefix": "CCXT_GATEWAY_ZMQ_"}

    broker_address: str = "tcp://127.0.0.1:5555"
    subprocess_connect: str = "tcp://127.0.0.1:5555"
    high_water_mark: int = 1000
    timeout_ms: int = 30000


class ProcessManagerConfig(BaseSettings):
    """Process manager configuration."""

    model_config = {"env_prefix": "CCXT_GATEWAY_PM_"}

    max_rss_mb: int = 512
    check_interval: int = 30
    auto_restart: bool = True
    max_restarts_per_hour: int = 5
    startup_timeout: int = 30


class UpdateConfig(BaseSettings):
    """Update configuration."""

    model_config = {"env_prefix": "CCXT_GATEWAY_UPDATE_"}

    check_interval_hours: int = 24
    auto_update: bool = False
    pypi_package: str = "ccxt"


class ExchangesConfig(BaseSettings):
    """Default exchanges configuration."""

    model_config = {"env_prefix": "CCXT_GATEWAY_EXCHANGES_"}

    default_enable_rate_limit: bool = True
    default_timeout: int = 30000
    default_verbose: bool = False


class IdleConfig(BaseSettings):
    """Idle shutdown configuration."""

    model_config = {"env_prefix": "CCXT_GATEWAY_IDLE_"}

    timeout_minutes: int = 5
    pidfile_path: str = "/tmp/ccxt_gateway.pid"


class Settings:
    """Main settings class."""

    def __init__(self, yaml_path: Optional[str] = None) -> None:
        self.server: ServerConfig = ServerConfig()
        self.zmq: ZMQConfig = ZMQConfig()
        self.process_manager: ProcessManagerConfig = ProcessManagerConfig()
        self.update: UpdateConfig = UpdateConfig()
        self.exchanges: ExchangesConfig = ExchangesConfig()
        self.idle: IdleConfig = IdleConfig()

        if yaml_path is None:
            for path in ["config/default.yaml", "ccxt-gateway/config/default.yaml"]:
                if os.path.exists(path):
                    yaml_path = path
                    break

        if yaml_path and os.path.exists(yaml_path):
            self._load_yaml(yaml_path)

    def _load_yaml(self, yaml_path: str) -> None:
        """Load settings from YAML file."""
        with open(yaml_path, "r") as f:
            data: Dict[str, Any] = yaml.safe_load(f)

        for section_name, _ in [
            ("server", ServerConfig),
            ("zmq", ZMQConfig),
            ("process_manager", ProcessManagerConfig),
            ("update", UpdateConfig),
            ("exchanges", ExchangesConfig),
            ("idle", IdleConfig),
        ]:
            if section_name in data:
                section_data: Dict[str, Any] = data[section_name]
                section_obj: Any = getattr(self, section_name)
                for key, value in section_data.items():
                    if hasattr(section_obj, key):
                        setattr(section_obj, key, value)


# Global settings instance
settings: Settings = Settings()
