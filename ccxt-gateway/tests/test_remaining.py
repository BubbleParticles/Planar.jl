"""Tests for remaining coverage gaps."""

import asyncio
import sys
from unittest.mock import MagicMock, patch, AsyncMock

import pytest

from ccxt_gateway.main import main
from ccxt_gateway.api import rest, admin


class TestMainRemaining:
    """Tests for remaining lines in main.py."""

    def test_main_uvloop_not_available(self):
        """Test main() runs without error when uvloop import fails."""
        with patch('ccxt_gateway.main.uvicorn.run') as mock_run, \
             patch('ccxt_gateway.main.asyncio.set_event_loop_policy'), \
             patch.dict('sys.modules', {'uvloop': None}):

            main()

            mock_run.assert_called_once()

    def test_main_uvloop_available(self):
        """Test main() when uvloop is available."""
        with patch('ccxt_gateway.main.uvicorn.run') as mock_run, \
             patch('ccxt_gateway.main.asyncio.set_event_loop_policy'):

            # Mock uvloop to be available
            mock_uvloop = MagicMock()
            with patch.dict('sys.modules', {'uvloop': mock_uvloop}):
                main()

            mock_run.assert_called_once()


class TestRestAPIRemaining:
    """Tests for remaining lines in rest.py."""

    def test_get_process_manager_none(self):
        """Test get_process_manager when None."""
        from fastapi import FastAPI, Request
        from fastapi.testclient import TestClient

        app = FastAPI()
        app.state.process_manager = None

        # Call get_process_manager
        from ccxt_gateway.api.rest import get_process_manager
        from fastapi import HTTPException

        mock_request = MagicMock(spec=Request)
        mock_request.app.state = app.state

        with pytest.raises(HTTPException) as exc_info:
            get_process_manager(mock_request)
        assert exc_info.value.status_code == 503
        assert "not initialized" in exc_info.value.detail.lower()

    def test_get_broker_none(self):
        """Test get_broker when None."""
        from fastapi import FastAPI, Request
        from fastapi.testclient import TestClient

        app = FastAPI()
        app.state.broker = None

        # Call get_broker
        from ccxt_gateway.api.rest import get_broker
        from fastapi import HTTPException

        mock_request = MagicMock(spec=Request)
        mock_request.app.state = app.state

        with pytest.raises(HTTPException) as exc_info:
            get_broker(mock_request)
        assert exc_info.value.status_code == 503
        assert "not initialized" in exc_info.value.detail.lower()


class TestAdminAPIRemaining:
    """Tests for remaining lines in admin.py."""

    def test_get_process_manager_none(self):
        """Test get_process_manager when None."""
        from fastapi import FastAPI, Request
        from fastapi.testclient import TestClient

        app = FastAPI()
        app.state.process_manager = None

        # Call get_process_manager
        from ccxt_gateway.api.admin import get_process_manager
        from fastapi import HTTPException

        mock_request = MagicMock(spec=Request)
        mock_request.app.state = app.state

        with pytest.raises(HTTPException) as exc_info:
            get_process_manager(mock_request)
        assert exc_info.value.status_code == 503
        assert "not initialized" in exc_info.value.detail.lower()

    def test_get_broker_none(self):
        """Test get_broker when None."""
        from fastapi import FastAPI, Request
        from fastapi.testclient import TestClient

        app = FastAPI()
        app.state.broker = None

        # Call get_broker
        from ccxt_gateway.api.admin import get_broker
        from fastapi import HTTPException

        mock_request = MagicMock(spec=Request)
        mock_request.app.state = app.state

        with pytest.raises(HTTPException) as exc_info:
            get_broker(mock_request)
        assert exc_info.value.status_code == 503
        assert "not initialized" in exc_info.value.detail.lower()

    def test_update_ccxt_endpoint_no_update(self):
        """Test /admin/update/ccxt when no update available."""
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app

        mock_broker = MagicMock()
        app.state.broker = mock_broker

        with patch('ccxt_gateway.utils.updates.check_update', return_value=(False, "1.0.0", "1.0.0")):
            client = TestClient(app)
            response = client.post("/admin/update/ccxt")
            assert response.status_code == 200
            data = response.json()
            assert "no update" in data["status"].lower()

    def test_update_ccxt_endpoint_with_update_success(self):
        """Test /admin/update/ccxt when update available and successful."""
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app

        mock_broker = MagicMock()
        app.state.broker = mock_broker

        with patch('ccxt_gateway.utils.updates.check_update', return_value=(True, "1.0.0", "2.0.0")), \
             patch('ccxt_gateway.utils.updates.update_ccxt', return_value=(True, "Updated to 2.0.0")):
            client = TestClient(app)
            response = client.post("/admin/update/ccxt")
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "success"

    def test_update_ccxt_endpoint_with_update_failure(self):
        """Test /admin/update/ccxt when update available but fails."""
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app

        mock_broker = MagicMock()
        app.state.broker = mock_broker

        with patch('ccxt_gateway.utils.updates.check_update', return_value=(True, "1.0.0", "2.0.0")), \
             patch('ccxt_gateway.utils.updates.update_ccxt', return_value=(False, "Update failed")):
            client = TestClient(app)
            response = client.post("/admin/update/ccxt")
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "failed"
