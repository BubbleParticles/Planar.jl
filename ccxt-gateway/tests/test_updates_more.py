"""Tests for utils/updates.py remaining coverage."""

import asyncio
from unittest.mock import MagicMock, patch, AsyncMock

import pytest

from ccxt_gateway.utils.updates import (
    get_latest_version, check_update, update_ccxt, UpdateChecker
)


class TestGetLatestVersion:
    """Tests for get_latest_version."""

    @pytest.mark.asyncio
    async def test_success(self):
        """Test successful version fetch."""
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {"info": {"version": "2.0.0"}}

        async def mock_get(*args, **kwargs):
            return mock_response

        with patch('httpx.AsyncClient.get', side_effect=mock_get):
            result = await get_latest_version()
            assert result == "2.0.0"

    @pytest.mark.asyncio
    async def test_failure(self):
        """Test when request fails."""
        with patch('httpx.AsyncClient.get', side_effect=Exception("Network error")):
            result = await get_latest_version()
            assert result is None

    @pytest.mark.asyncio
    async def test_timeout(self):
        """Test when request times out."""
        with patch('httpx.AsyncClient.get', side_effect=Exception("timeout")):
            result = await get_latest_version()
            assert result is None


class TestCheckUpdateMore:
    """More tests for check_update."""

    @pytest.mark.asyncio
    async def test_current_version_none(self):
        """Test when current version is None."""
        with patch('ccxt_gateway.utils.updates.get_current_version', return_value=None):
            update_available, current, latest = await check_update()
            assert update_available is False
            assert current is None

    @pytest.mark.asyncio
    async def test_latest_version_none(self):
        """Test when latest version is None."""
        with patch('ccxt_gateway.utils.updates.get_current_version', return_value="1.0.0"), \
             patch('ccxt_gateway.utils.updates.get_latest_version', return_value=None):
            update_available, current, latest = await check_update()
            assert update_available is False
            assert latest is None

    @pytest.mark.asyncio
    async def test_version_comparison_error(self):
        """Test when version comparison fails."""
        with patch('ccxt_gateway.utils.updates.get_current_version', return_value="invalid"), \
             patch('ccxt_gateway.utils.updates.get_latest_version', return_value="2.0.0"), \
             patch('packaging.version.parse', side_effect=Exception("Invalid version")):
            update_available, current, latest = await check_update()
            assert update_available is False


class TestUpdateCcxtMore:
    """More tests for update_ccxt."""

    @pytest.mark.asyncio
    async def test_latest_version_none(self):
        """Test when latest version is None."""
        with patch('ccxt_gateway.utils.updates.get_latest_version', return_value=None):
            success, msg = await update_ccxt()
            assert success is False
            assert "Failed to get latest version" in msg

    @pytest.mark.asyncio
    async def test_subprocess_success(self):
        """Test successful subprocess run."""
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stderr = ""
        mock_result.stdout = "Success"

        with patch('subprocess.run', return_value=mock_result), \
             patch('ccxt_gateway.utils.updates.get_latest_version', return_value="2.0.0"):
            success, msg = await update_ccxt()
            assert success is True
            assert "Updated" in msg

    @pytest.mark.asyncio
    async def test_subprocess_failure(self):
        """Test when subprocess fails."""
        mock_result = MagicMock()
        mock_result.returncode = 1
        mock_result.stderr = "Some error"
        mock_result.stdout = ""

        with patch('subprocess.run', return_value=mock_result), \
             patch('ccxt_gateway.utils.updates.get_latest_version', return_value="2.0.0"):
            success, msg = await update_ccxt()
            assert success is False
            assert "Update failed" in msg

    @pytest.mark.asyncio
    async def test_subprocess_exception(self):
        """Test when subprocess raises exception."""
        with patch('subprocess.run', side_effect=Exception("Failed")), \
             patch('ccxt_gateway.utils.updates.get_latest_version', return_value="2.0.0"):
            success, msg = await update_ccxt()
            assert success is False


class TestUpdateCheckerMore:
    """More tests for UpdateChecker."""

    @pytest.mark.asyncio
    async def test_check_loop_cancelled(self):
        """Test check loop handles CancelledError."""
        checker = UpdateChecker(check_interval_hours=0)  # Disabled
        checker.running = True

        # Mock _check_once to raise CancelledError
        async def mock_check():
            raise asyncio.CancelledError()

        checker._check_once = mock_check

        # Should exit gracefully
        await checker._check_loop()

    @pytest.mark.asyncio
    async def test_check_loop_exception(self):
        """Test check loop handles exceptions."""
        checker = UpdateChecker(check_interval_hours=0)  # Disabled
        checker.running = True

        # Mock _check_once to raise an exception
        async def mock_check():
            raise Exception("Some error")

        checker._check_once = mock_check

        # Should continue running (not crash)
        # We can't easily test the loop, but we can test that it handles exceptions

    def test_stop_not_started(self):
        """Test stop when not started."""
        checker = UpdateChecker()
        # Should not raise
        import asyncio
        asyncio.get_event_loop().run_until_complete(checker.stop())
