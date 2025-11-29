FROM julia:1.12 AS base
RUN mkdir /planar \
    && apt-get update \
    && apt-get -y install sudo direnv jq git \
    && useradd -u 1000 -G sudo -U -m -s /bin/bash plnuser \
    && chown plnuser:plnuser /planar \
    # Allow sudoers
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
ENV JULIA_NOPRECOMP=""
ENV JULIA_PRECOMP=Remote,PaperMode,LiveMode,Fetch,Optim,Plotting
CMD $JULIA_BIN -C "$JULIA_CPU_TARGET"

FROM base AS python
ENV JULIA_LOAD_PATH=:/planar
ENV JULIA_CONDAPKG_ENV=/planar/user/.conda
# avoids progressbar spam
ENV CI=true
COPY --chown=plnuser:plnuser ./Lang/ /planar/Lang/
COPY --chown=plnuser:plnuser ./Python/*.toml /planar/Python/
# Instantiate python env since CondaPkg is pulled from master
ARG CACHE=1
RUN $JULIA_CMD --project=/planar/Python -e "import Pkg; Pkg.instantiate()"
COPY --chown=plnuser:plnuser ./Python /planar/Python
RUN $JULIA_CMD --project=/planar/Python -e "using Python"

FROM python AS precomp-base
ARG CACHE=1
ENV JULIA_NUM_THREADS=auto
ENV JULIA_PROJECT=/planar/Planar
USER plnuser
WORKDIR /planar
RUN JULIA_PROJECT= $JULIA_CMD -e "import Pkg; Pkg.add([\"DataFrames\", \"CSV\", \"ZipFile\"])"
COPY --chown=plnuser:plnuser ./ /planar/
RUN touch /planar/user/.envrc; mkdir /planar/.conda
RUN git submodule update --init
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
RUN $JULIA_CMD -e "using Metrics"

FROM planar-precomp AS planar-precomp-interactive
ENV JULIA_PROJECT=/planar/PlanarInteractive
RUN JULIA_PROJECT= $JULIA_CMD -e "import Pkg; Pkg.add([\"Makie\", \"WGLMakie\"])"
RUN $JULIA_CMD -e "import Pkg; Pkg.instantiate()"
RUN $JULIA_CMD -e "using PlanarInteractive"


FROM planar-precomp AS planar-sysimage
USER root
RUN apt-get install -y gcc g++
ENV JULIA_PROJECT=/planar/user/Load
ENV CACHE=1
ARG COMPILE_SCRIPT
ARG NTHREADS=auto
ARG PLANAR_BITMEX_SANDBOX_APIKEY
ARG PLANAR_BITMEX_SANDBOX_SECRET
ARG PLANAR_BITMEX_SANDBOX_PASSWORD
ARG PLANAR_PHEMEX_SANDBOX_APIKEY
ARG PLANAR_PHEMEX_SANDBOX_SECRET
ARG PLANAR_PHEMEX_SANDBOX_PASSWORD
RUN scripts/docker_compile.sh; \
    su plnuser -c "cd /planar; \
    . .envrc; \
    cat /tmp/compile.jl; \
    $JULIA_CMD -t ${NTHREADS} -e \
    'include(\"/tmp/compile.jl\"); compile(\"user/Load\"; cpu_target=\"$JULIA_CPU_TARGET\")'"; \
    rm -rf /tmp/compile.jl
USER plnuser
ENV JULIA_PROJECT=/planar/Planar
# Resets condapkg env
RUN $JULIA_CMD --sysimage "/planar/Planar.so" -e "using Planar"
CMD $JULIA_CMD --sysimage "/planar/Planar.so"

FROM planar-precomp-interactive AS planar-sysimage-interactive
USER root
ENV CI=true
ENV JULIA_PROJECT=/planar/PlanarInteractive
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
    su plnuser -c "cd /planar; \
    . .envrc; \
    echo \"compiling with cpu target $JULIA_CPU_TARGET\"; \
    cat /tmp/compile.jl; \
    $JULIA_CMD -e \
    'include(\"/tmp/compile.jl\"); compile(\"PlanarInteractive\"; cpu_target=\"$JULIA_CPU_TARGET\")'"; \
    rm -rf /tmp/compile.jl
USER plnuser
RUN $JULIA_CMD --sysimage "/planar/Planar.so" -e "using PlanarInteractive"
CMD $JULIA_CMD --sysimage Planar.so
