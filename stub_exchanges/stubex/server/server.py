"""HTTP server that serves stub data for ccxt exchanges.

This server intercepts ccxt API requests and returns deterministic stub data
while preserving ccxt's request/response logic as much as possible.
"""

import json
import logging
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import time
import sys
import os

# Add parent to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from stubex.utils import (
        generate_ohlcv,
        generate_orderbook,
        generate_balance,
        generate_trades,
    )
    from stubex.utils import deterministic_random
except ImportError:
    from utils import (
        generate_ohlcv,
        generate_orderbook,
        generate_balance,
        generate_trades,
    )
    from utils import deterministic_random

logger = logging.getLogger(__name__)


class StubRequestHandler(BaseHTTPRequestHandler):
    """HTTP request handler that returns stub data for ccxt requests."""

    # Exchange-specific configuration
    exchange_id = "binance"
    stub_server = None

    def log_message(self, format, *args):
        """Suppress default logging."""
        pass

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        # Skip CORS preflight
        if path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')
            return

        # Route to appropriate handler
        try:
            if "/ticker" in path:
                self._handle_ticker(path, query)
            elif "/depth" in path or "/orderbook" in path:
                self._handle_orderbook(path, query)
            elif "/klines" in path or "/ohlcv" in path:
                self._handle_ohlcv(path, query)
            elif "/trades" in path:
                self._handle_trades(path, query)
            elif "/ticker/24hr" in path:
                self._handle_ticker_24hr(path, query)
            elif "/exchangeInfo" in path or "/symbols" in path:
                self._handle_exchange_info(path, query)
            elif "/time" in path:
                self._handle_time(path, query)
            elif "/balance" in path:
                self._handle_balance(path, query)
            else:
                self._send_error(404, f"Unknown endpoint: {path}")
        except Exception as e:
            logger.exception(f"Error handling request: {e}")
            self._send_error(500, str(e))

    def do_POST(self):
        """Handle POST requests."""
        parsed = urlparse(self.path)
        path = parsed.path

        # Read request body
        content_length = int(self.headers.get("Content-Length", 0))
        body = (
            self.rfile.read(content_length).decode("utf-8")
            if content_length > 0
            else ""
        )

        try:
            if "/order" in path:
                self._handle_create_order(path, body)
            elif "/cancel" in path:
                self._handle_cancel_order(path, body)
            elif "/openOrders" in path or "/orders" in path:
                self._handle_orders(path, body)
            elif "/myTrades" in path:
                self._handle_my_trades(path, body)
            elif "/position" in path:
                self._handle_positions(path, body)
            elif "/leverage" in path:
                self._handle_leverage(path, body)
            else:
                self._send_error(404, f"Unknown endpoint: {path}")
        except Exception as e:
            logger.exception(f"Error handling POST request: {e}")
            self._send_error(500, str(e))

    def _handle_ticker(self, path, query):
        """Handle ticker requests."""
        symbol = query.get("symbol", ["BTCUSDT"])[0]

        # Generate deterministic data based on symbol
        rng = deterministic_random(self.exchange_id + symbol)
        price = 1000 + (rng.randint(0, 10000))
        volume = 100 + (rng.randint(0, 1000))

        data = {
            "symbol": symbol,
            "lastPrice": str(price),
            "priceChange": str(price * 0.01),
            "priceChangePercent": "1.0",
            "weightedAvgPrice": str(price * 0.99),
            "prevClosePrice": str(price * 0.99),
            "lastQty": str(volume),
            "bidPrice": str(price * 0.999),
            "bidQty": str(volume * 0.5),
            "askPrice": str(price * 1.001),
            "askQty": str(volume * 0.5),
            "openPrice": str(price * 0.98),
            "highPrice": str(price * 1.05),
            "lowPrice": str(price * 0.95),
            "volume": str(volume * 1000),
            "quoteVolume": str(volume * price * 1000),
            "count": int(volume * 10),
        }

        self._send_json([data])

    def _handle_ticker_24hr(self, path, query):
        """Handle 24hr ticker requests."""
        symbol = query.get("symbol", ["BTCUSDT"])[0]

        # Generate deterministic data based on symbol
        rng = deterministic_random(self.exchange_id + symbol)
        price = 1000 + (rng.randint(0, 10000))
        volume = 100 + (rng.randint(0, 1000))

        data = {
            "symbol": symbol,
            "lastPrice": str(price),
            "priceChange": str(price * 0.01),
            "priceChangePercent": "1.0",
            "weightedAvgPrice": str(price * 0.99),
            "prevClosePrice": str(price * 0.99),
            "lastQty": str(volume),
            "bidPrice": str(price * 0.999),
            "bidQty": str(volume * 0.5),
            "askPrice": str(price * 1.001),
            "askQty": str(volume * 0.5),
            "openPrice": str(price * 0.98),
            "highPrice": str(price * 1.05),
            "lowPrice": str(price * 0.95),
            "volume": str(volume * 1000),
            "quoteVolume": str(volume * price * 1000),
            "count": int(volume * 10),
        }

        self._send_json(data)

    def _handle_orderbook(self, path, query):
        """Handle orderbook requests."""
        symbol = query.get("symbol", ["BTCUSDT"])[0]
        limit = int(query.get("limit", [20])[0])
        limit = min(limit, 100)  # Cap at 100

        # Generate deterministic orderbook
        rng = deterministic_random(self.exchange_id + symbol)
        price = 1000 + (rng.randint(0, 10000))

        bids = []
        asks = []
        for i in range(limit):
            offset = i * 0.01
            # Use large quantities to ensure any reasonable order can be filled
            bid_price = price * (1 - offset)
            ask_price = price * (1 + offset)
            amount = str(1_000_000)  # large amount
            bids.append([str(bid_price), amount])
            asks.append([str(ask_price), amount])

        data = {
            "lastUpdateId": int(time.time() * 1000),
            "bids": bids,
            "asks": asks,
        }

        self._send_json(data)

    def _handle_ohlcv(self, path, query):
        """Handle OHLCV/klines requests."""
        symbol = query.get("symbol", ["BTCUSDT"])[0]
        interval = query.get("interval", ["1m"])[0]
        limit = int(query.get("limit", [100])[0])

        # Generate OHLCV data
        ohlcv_data = generate_ohlcv(symbol, None, limit, 1)

        # Convert to Binance format
        result = []
        for candle in ohlcv_data:
            result.append(
                [
                    candle[0],  # Open time
                    str(candle[1]),  # Open
                    str(candle[2]),  # High
                    str(candle[3]),  # Low
                    str(candle[4]),  # Close
                    str(candle[5]),  # Volume
                    candle[0] + 60000,  # Close time
                    str(candle[5] * candle[4]),  # Quote asset volume
                    100,  # Number of trades
                    str(candle[5] * 0.5),  # Taker buy base
                    str(candle[5] * candle[4] * 0.5),  # Taker buy quote
                ]
            )

        self._send_json(result)

    def _handle_trades(self, path, query):
        """Handle public trades requests."""
        symbol = query.get("symbol", ["BTCUSDT"])[0]
        limit = int(query.get("limit", [100])[0])

        trades = generate_trades(symbol, limit)

        result = []
        for trade in trades:
            result.append(
                {
                    "id": str(trade["id"]),
                    "price": str(trade["price"]),
                    "qty": str(trade["amount"]),
                    "time": trade["timestamp"],
                    "isBuyerMaker": False,
                }
            )

        self._send_json(result)

    def _handle_exchange_info(self, path, query):
        """Handle exchange info / symbols endpoint."""
        symbols = query.get("symbols", ["BTCUSDT", "ETHUSDT", "SOLUSDT"])

        result = {
            "timezone": "UTC",
            "serverTime": int(time.time() * 1000),
            "symbols": [],
        }

        base_symbols = ["BTC", "ETH", "SOL", "XRP", "ADA", "DOGE", "MATIC"]
        quote_symbols = ["USDT", "BUSD", "BTC", "ETH"]

        for base in base_symbols:
            for quote in quote_symbols:
                if base == quote:
                    continue
                symbol = base + quote

                result["symbols"].append(
                    {
                        "symbol": symbol,
                        "baseAsset": base,
                        "quoteAsset": quote,
                        "status": "TRADING",
                        "spot": True,
                        "margin": True,
                        "option": False,
                        "contract": False,
                        "filters": [
                            {
                                "filterType": "PRICE_FILTER",
                                "minPrice": "0.01",
                                "maxPrice": "1000000",
                                "tickSize": "0.01",
                            },
                            {
                                "filterType": "LOT_SIZE",
                                "minQty": "0.001",
                                "maxQty": "1000000",
                                "stepSize": "0.001",
                            },
                        ],
                    }
                )

        self._send_json(result)

    def _handle_time(self, path, query):
        """Handle time endpoint."""
        self._send_json({"serverTime": int(time.time() * 1000)})

    def _handle_balance(self, path, query):
        """Handle balance query."""
        data = {
            "canTrade": True,
            "canWithdraw": True,
            "canDeposit": True,
            "updateTime": int(time.time() * 1000),
            "balances": [
                {"asset": "BTC", "free": "1.0", "locked": "0.0"},
                {"asset": "ETH", "free": "10.0", "locked": "0.0"},
                {"asset": "USDT", "free": "10000.0", "locked": "0.0"},
            ],
        }
        self._send_json(data)

    def _handle_create_order(self, path, body):
        """Handle order creation."""
        params = parse_qs(body)

        symbol = params.get("symbol", ["BTCUSDT"])[0]
        side = params.get("side", ["BUY"])[0]
        order_type = params.get("type", ["MARKET"])[0]
        quantity = float(params.get("quantity", ["0"])[0])

        # Generate deterministic order data
        rng = deterministic_random(self.exchange_id + symbol + str(time.time()))
        price = 1000 + (rng.randint(0, 10000))

        order_id = rng.randint(0, 1000000)

        data = {
            "symbol": symbol,
            "orderId": order_id,
            "orderListId": -1,
            "clientOrderId": f"stub_{order_id}",
            "transactTime": int(time.time() * 1000),
            "price": str(price),
            "origQty": str(quantity),
            "executedQty": str(quantity),
            "cummulativeQuoteQty": str(quantity * price),
            "status": "FILLED",
            "timeInForce": "GTC",
            "type": order_type,
            "side": side,
            "fills": [
                {
                    "price": str(price),
                    "qty": str(quantity),
                    "commission": str(quantity * price * 0.001),
                    "commissionAsset": "BNB",
                }
            ],
        }

        self._send_json(data)

    def _handle_cancel_order(self, path, body):
        """Handle order cancellation."""
        params = parse_qs(body)

        symbol = params.get("symbol", ["BTCUSDT"])[0]
        order_id = params.get("orderId", ["12345"])[0]

        data = {
            "symbol": symbol,
            "orderId": int(order_id),
            "orderListId": -1,
            "clientOrderId": f"stub_{order_id}",
            "status": "CANCELED",
        }

        self._send_json(data)

    def _handle_orders(self, path, body):
        """Handle fetch orders."""
        self._send_json([])

    def _handle_my_trades(self, path, body):
        """Handle fetch my trades."""
        self._send_json([])

    def _handle_positions(self, path, body):
        """Handle positions."""
        self._send_json([])

    def _handle_leverage(self, path, body):
        """Handle leverage settings."""
        self._send_json({"leverage": 10})

    def _send_json(self, data):
        """Send JSON response."""
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def _send_error(self, code, message):
        """Send error response."""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps({"error": message}).encode("utf-8"))


class StubServer:
    """HTTP server that serves stub data for ccxt exchanges."""

    def __init__(self, host="127.0.0.1", port=8765):
        self.host = host
        self.port = port
        self.server = None
        self.thread = None
        self._lock = threading.Lock()

    @property
    def url(self):
        """Get the server URL."""
        return f"http://{self.host}:{self.port}"

    def start(self):
        """Start the server in a background thread."""
        with self._lock:
            if self.server is not None:
                return self.url

            # Set handler exchange_id
            StubRequestHandler.stub_server = self

            self.server = HTTPServer((self.host, self.port), StubRequestHandler)

            def run():
                logger.info(f"Starting stub server on {self.host}:{self.port}")
                self.server.serve_forever()

            self.thread = threading.Thread(target=run, daemon=True)
            self.thread.start()

            return self.url

    def stop(self):
        """Stop the server."""
        with self._lock:
            if self.server is not None:
                self.server.shutdown()
                self.server = None
                self.thread = None

    @property
    def url(self):
        """Get the server URL."""
        return f"http://{self.host}:{self.port}"


# Global server instance
_server_instance = None
_server_lock = threading.Lock()


def get_stub_server():
    """Get the global stub server instance."""
    global _server_instance
    return _server_instance


def start_stub_server(host="127.0.0.1", port=8765):
    """Start or get the stub server."""
    global _server_instance

    with _server_lock:
        if _server_instance is None:
            _server_instance = StubServer(host, port)
            _server_instance.start()
        return _server_instance
