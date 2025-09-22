using Watchers: watcher, Watcher, _view, _val, logerror
using ..BlockchainInfo
using ..Etherscan
using ..Helius

const BlockchainAddressVal = Val{:blockchain_address}

function blockchain_address_watcher(
    chain::Symbol,
    address::AbstractString;
    api_key::AbstractString="",
    fetch_interval=Second(60),
    kwargs...
)
    if chain == :ethereum
        Etherscan.set_api_key!(api_key)
    elseif chain == :solana
        Helius.set_api_key!(api_key)
    end

    attrs = Dict{Symbol,Any}(
        :chain => chain,
        :address => address,
        :last_tx_hash => nothing, # Used to check for new transactions
        :last_offset => 0, # For bitcoin
        :last_page => 1, # For ethereum
        :last_signature => nothing # For solana
    )

    watcher(
        Vector{Dict}, # The watcher will store a list of transaction dicts
        string("blockchain_address_", chain, "_", address),
        BlockchainAddressVal();
        fetch_interval=fetch_interval,
        attrs=attrs,
        kwargs...
    )
end

function _fetch!(w::Watcher, ::BlockchainAddressVal)
    chain = w.attrs[:chain]
    address = w.attrs[:address]

    try
        if chain == :bitcoin
            _fetch_bitcoin!(w, address)
        elseif chain == :ethereum
            _fetch_ethereum!(w, address)
        elseif chain == :solana
            _fetch_solana!(w, address)
        else
            logerror(w, "Unsupported chain: $chain")
            return false
        end
        return true
    catch e
        logerror(w, e, stacktrace(catch_backtrace()))
        return false
    end
end

function _fetch_bitcoin!(w::Watcher, address)
    # For bitcoin, we use offset. We fetch the first page and check the hash of the first tx.
    # If it's the same as the last one we saw, we stop. Otherwise, we process the new txs.
    # This is not perfect, as a reorg could change the order of transactions.
    # A more robust solution would be to use a websocket API, but that's more complex.

    data = BlockchainInfo.get_address_transactions(address, limit=50, offset=w.attrs[:last_offset])
    if data !== nothing && !isempty(data["txs"])
        txs = data["txs"]
        current_tx_hash = txs[1]["hash"]

        if w.attrs[:last_tx_hash] != current_tx_hash
            # New transactions found
            new_txs = []
            for tx in txs
                if tx["hash"] == w.attrs[:last_tx_hash]
                    break
                end
                push!(new_txs, tx)
            end

            if !isempty(new_txs)
                push!(w.buffer, (time=now(), value=reverse(new_txs))) # reverse to get chronological order
                w.attrs[:last_tx_hash] = current_tx_hash
            end
        end
    end
end

function _fetch_ethereum!(w::Watcher, address)
    # Etherscan returns transactions in descending order by default.
    # We can fetch the first page and compare the hash of the first tx.
    data = Etherscan.get_address_transactions(address, page=1, offset=50, sort="desc")
    if data !== nothing && !isempty(data)
        current_tx_hash = data[1]["hash"]

        if w.attrs[:last_tx_hash] != current_tx_hash
            new_txs = []
            for tx in data
                if tx["hash"] == w.attrs[:last_tx_hash]
                    break
                end
                push!(new_txs, tx)
            end

            if !isempty(new_txs)
                push!(w.buffer, (time=now(), value=reverse(new_txs)))
                w.attrs[:last_tx_hash] = current_tx_hash
            end
        end
    end
end

function _fetch_solana!(w::Watcher, address)
    # Helius returns transactions in descending order.
    # We can use the `before` parameter to get transactions before the last one we saw.
    # However, for simplicity, we'll just fetch the latest transactions and check the signature.
    data = Helius.get_address_transactions(address, limit=50)
    if data !== nothing && !isempty(data)
        current_tx_sig = data[1]["signature"]

        if w.attrs[:last_signature] != current_tx_sig
            new_txs = []
            for tx in data
                if tx["signature"] == w.attrs[:last_signature]
                    break
                end
                push!(new_txs, tx)
            end

            if !isempty(new_txs)
                push!(w.buffer, (time=now(), value=reverse(new_txs)))
                w.attrs[:last_signature] = current_tx_sig
            end
        end
    end
end
