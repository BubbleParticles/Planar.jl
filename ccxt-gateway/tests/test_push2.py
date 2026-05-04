"""Test for utils/updates.py remaining lines."""
import builtins
import pytest
from unittest.mock import MagicMock, patch, AsyncMock
from ccxt_gateway.utils.updates import get_current_version, get_latest_version, check_update, update_ccxt

class TestUtilsPush:
    def test_get_current_version_no_ccxt(self):
        original_import = builtins.__import__
        def mock_import(name, *args, **kwargs):
            if name == 'ccxt':
                raise ImportError("No module named 'ccxt'")
            return original_import(name, *args, **kwargs)
        with patch('builtins.__import__', side_effect=mock_import):
            result = get_current_version()
            assert result is None

    @pytest.mark.asyncio
    async def test_get_latest_version_exception(self):
        with patch('httpx.AsyncClient.get', side_effect=Exception("Network error")):
            result = await get_latest_version()
            assert result is None

    @pytest.mark.asyncio
    async def test_check_update_no_current(self):
        with patch('ccxt_gateway.utils.updates.get_current_version', return_value=None):
            update_available, current, latest = await check_update()
            assert update_available is False
            assert current is None

    @pytest.mark.asyncio
    async def test_update_ccxt_no_latest(self):
        with patch('ccxt_gateway.utils.updates.get_latest_version', return_value=None):
            success, msg = await update_ccxt()
            assert success is False
            assert "Failed to get latest version" in msg

    @pytest.mark.asyncio
    async def test_check_update_version_error(self):
        with patch('ccxt_gateway.utils.updates.get_current_version', return_value="invalid"), \
             patch('ccxt_gateway.utils.updates.get_latest_version', return_value="2.0.0"), \
             patch('packaging.version.parse', side_effect=Exception("Invalid version")):
            update_available, current, latest = await check_update()
            assert update_available is False
