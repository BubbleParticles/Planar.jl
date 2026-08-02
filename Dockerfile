FROM julia:1.12 AS base
RUN mkdir /planar \
    && mkdir -p /planar/user \
    && apt-get update \
    && apt-get -y install sudo direnv jq git \
    && useradd -m -s /bin/bash plnuser \
    && chown -R plnuser:plnuser /planar \
    && echo "plnuser ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers
WORKDIR /planar
USER plnuser
ARG CPU_TARGET="generic"
RUN echo "cpu target is $CPU_TARGET"
ENV JULIA_BIN=/usr/local/julia/bin/julia
ARG JULIA_CMD="$JULIA_BIN -C $CPU_TARGET"
ENV JULIA_CMD=$JULIA_CMD
ENV JULIA_CPU_TARGET ${CPU_TARGET}

# PLANAR ENV VARS GO HERE
ENV PLANAR_LIQUIDATION_BUFFER=0.02
ENV JULIA_PRECOMP=PlanarCore,Planar,PlanarOptim
ENV JULIA_FULL_PRECOMP=PlanarCore,Planar,PlanarOptim
CMD $JULIA_BIN -C "$JULIA_CPU_TARGET"

FROM base AS python
ENV JULIA_LOAD_PATH=:/planar
ENV JULIA_CONDAPKG_ENV=/planar/user/.conda
# avoids progressbar spam
ENV CI=true
# Instantiate python env since CondaPkg is pulled from master
ARG CACHE=1
RUN $JULIA_CMD --project=/planar/Python -e "import Pkg; Pkg.instantiate()"
# Skip `using Python` here - conda env will be fully set up during full precompilation
FROM python AS precomp-base
ARG CACHE=1
ENV JULIA_NUM_THREADS=auto
ENV JULIA_PROJECT=/planar/Planar
USER plnuser
WORKDIR /planar
RUN JULIA_PROJECT= $JULIA_CMD -e "import Pkg; Pkg.add([\"DataFrames\", \"CSV\", \"ZipFile\"])"
COPY --chown=plnuser:plnuser ./ /planar/
RUN touch /planar/user/.envrc; mkdir /planar/.conda
RUN mkdir -p /planar/ccxt-gateway/.cache
CMD $JULIA_BIN -C "$JULIA_CPU_TARGET"

FROM precomp-base AS planar-precomp
ARG PLANAR_BITMEX_SANDBOX_APIKEY
ARG PLANAR_BITMEX_SANDBOX_SECRET
ARG PLANAR_BITMEX_SANDBOX_PASSWORD
ARG PLANAR_PHEMEX_SANDBOX_APIKEY
ARG PLANAR_PHEMEX_SANDBOX_SECRET
ARG PLANAR_PHEMEX_SANDBOX_PASSWORD
ENV JULIA_PROJECT=/planar/Planar
ENV CI=true
RUN $JULIA_CMD -e "import Pkg; Pkg.instantiate()"
RUN $JULIA_CMD -e "using Planar"

FROM planar-precomp AS planar-precomp-optim
ENV JULIA_PROJECT=/planar/PlanarOptim
RUN JULIA_PROJECT= $JULIA_CMD -e "import Pkg; Pkg.add([\"Makie\", \"WGLMakie\"])"
RUN $JULIA_CMD -e "import Pkg; Pkg.instantiate()"
RUN $JULIA_CMD -e "using PlanarOptim"


FROM planar-precomp AS planar-sysimage
USER root
RUN apt-get install -y gcc g++
ENV JULIA_PROJECT=/planar/user/Load
ENV CACHE=1
ENV CCXT_GATEWAY_DISABLE=true
ARG COMPILE_SCRIPT
ARG NTHREADS=auto
ARG PLANAR_BITMEX_SANDBOX_APIKEY
ARG PLANAR_BITMEX_SANDBOX_SECRET
ARG PLANAR_BITMEX_SANDBOX_PASSWORD
ARG PLANAR_PHEMEX_SANDBOX_APIKEY
ARG PLANAR_PHEMEX_SANDBOX_SECRET
ARG PLANAR_PHEMEX_SANDBOX_PASSWORD
RUN scripts/docker_compile.sh; \
    if [ -f /planar/Planar.so ]; then \
        echo "Sysimage created successfully at /planar/Planar.so"; \
    else \
        echo "ERROR: Sysimage not found at /planar/Planar.so"; \
        exit 1; \
    fi; \
    rm -rf /tmp/compile.jl
USER plnuser
ENV JULIA_PROJECT=/planar/Planar
# Resets condapkg env
RUN $JULIA_CMD --sysimage "/planar/Planar.so" -e "using Planar"
CMD $JULIA_CMD --sysimage "/planar/Planar.so"

FROM planar-precomp-optim AS planar-sysimage-optim
USER root
ENV CI=true
ENV JULIA_PROJECT=/planar/PlanarOptim
ENV CCXT_GATEWAY_DISABLE=true
RUN apt-get install -y gcc g++
ARG COMPILE_SCRIPT
ARG NTHREADS=auto
ARG PLANAR_BITMEX_SANDBOX_APIKEY
ARG PLANAR_BITMEX_SANDBOX_SECRET
ARG PLANAR_BITMEX_SANDBOX_PASSWORD
ARG PLANAR_PHEMEX_SANDBOX_APIKEY
ARG PLANAR_PHEMEX_SANDBOX_SECRET
ARG PLANAR_PHEMEX_SANDBOX_PASSWORD
RUN scripts/docker_compile.sh; \
    if [ -f /planar/Planar.so ]; then \
        echo "Sysimage created successfully at /planar/Planar.so"; \
    else \
        echo "ERROR: Sysimage not found at /planar/Planar.so"; \
        exit 1; \
    fi; \
    rm -rf /tmp/compile.jl
USER plnuser
RUN $JULIA_CMD --sysimage "/planar/Planar.so" -e "using PlanarOptim"
CMD $JULIA_CMD --sysimage Planar.so