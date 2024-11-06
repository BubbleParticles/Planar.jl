FROM julia:1.11 as base
RUN mkdir /vindicta \
    && apt-get update \
    && apt-get -y install sudo direnv git \
    && useradd -u 1000 -G sudo -U -m -s /bin/bash vdtuser \
    && chown vdtuser:vdtuser /vindicta \
    # Allow sudoers
    && echo "vdtuser ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers
WORKDIR /vindicta
USER vdtuser
ARG CPU_TARGET=generic
ENV JULIA_BIN=/usr/local/julia/bin/julia
ARG JULIA_CMD="$JULIA_BIN -C $CPU_TARGET"
ENV JULIA_CMD=$JULIA_CMD
ENV JULIA_CPU_TARGET ${CPU_TARGET}

# VINDICTA ENV VARS GO HERE
ENV VINDICTA_LIQUIDATION_BUFFER=0.02
ENV JULIA_NOPRECOMP=""
ENV JULIA_PRECOMP=Remote,PaperMode,LiveMode,Fetch,Optimization,Plotting
CMD $JULIA_BIN -C $JULIA_CPU_TARGET

FROM base as python1
ENV JULIA_LOAD_PATH=:/vindicta
ENV JULIA_CONDAPKG_ENV=/vindicta/user/.conda
# avoids progressbar spam
ENV CI=true
COPY --chown=vdtuser:vdtuser ./Lang/ /vindicta/Lang/
COPY --chown=vdtuser:vdtuser ./Python/*.toml /vindicta/Python/
# Instantiate python env since CondaPkg is pulled from master
ARG CACHE=1
RUN $JULIA_CMD --project=/vindicta/Python -e "import Pkg; Pkg.instantiate()"
COPY --chown=vdtuser:vdtuser ./Python /vindicta/Python
RUN $JULIA_CMD --project=/vindicta/Python -e "using Python"

FROM python1 as precompile1
COPY --chown=vdtuser:vdtuser ./Vindicta/*.toml /vindicta/Vindicta/
ENV JULIA_PROJECT=/vindicta/Vindicta
ARG CACHE=1
RUN $JULIA_CMD --project=/vindicta/Vindicta -e "import Pkg; Pkg.instantiate()"

FROM precompile1 as precompile2
RUN JULIA_PROJECT= $JULIA_CMD -e "import Pkg; Pkg.add([\"DataFrames\", \"CSV\", \"ZipFile\"])"

FROM precompile2 as precompile3
COPY --chown=vdtuser:vdtuser ./ /vindicta/
RUN git submodule update --init

FROM precompile3 as precomp-base
USER vdtuser
WORKDIR /vindicta
ENV JULIA_NUM_THREADS=auto
CMD $JULIA_BIN -C $JULIA_CPU_TARGET

FROM precomp-base as vindicta-precomp
ENV JULIA_PROJECT=/vindicta/Vindicta
RUN $JULIA_CMD -e "import Pkg; Pkg.instantiate()"
RUN $JULIA_CMD -e "using Vindicta; using Metrics"
RUN $JULIA_CMD -e "using Metrics"

FROM vindicta-precomp as vindicta-precomp-interactive
ENV JULIA_PROJECT=/vindicta/VindictaInteractive
RUN JULIA_PROJECT= $JULIA_CMD -e "import Pkg; Pkg.add([\"Makie\", \"WGLMakie\"])"
RUN $JULIA_CMD -e "import Pkg; Pkg.instantiate()"
RUN $JULIA_CMD -e "using VindictaInteractive"


FROM vindicta-precomp as vindicta-sysimage
USER root
RUN apt-get install -y gcc g++
ENV JULIA_PROJECT=/vindicta/user/Load
ARG COMPILE_SCRIPT
RUN scripts/docker_compile.sh; \
    su vdtuser -c "cd /vindicta; \
    . .envrc; \
    cat /tmp/compile.jl; \
    $JULIA_CMD -e \
    'include(\"/tmp/compile.jl\"); compile(\"user/Load\"; cpu_target=\"$JULIA_CPU_TARGET\")'"; \
    rm -rf /tmp/compile.jl
USER vdtuser
ENV JULIA_PROJECT=/vindicta/Vindicta
# Resets condapkg env
RUN $JULIA_CMD --sysimage "/vindicta/Vindicta.so" -e "using Vindicta"
CMD $JULIA_CMD --sysimage "/vindicta/Vindicta.so"

FROM vindicta-precomp-interactive as vindicta-sysimage-interactive
USER root
ENV JULIA_PROJECT=/vindicta/VindictaInteractive
RUN apt-get install -y gcc g++
ARG COMPILE_SCRIPT
RUN scripts/docker_compile.sh; \
    su vdtuser -c "cd /vindicta; \
    . .envrc; \
    cat /tmp/compile.jl; \
    $JULIA_CMD -e \
    'include(\"/tmp/compile.jl\"); compile(\"VindictaInteractive\"; cpu_target=\"$JULIA_CPU_TARGET\")'"; \
    rm -rf /tmp/compile.jl
USER vdtuser
# Resets condapkg env
RUN $JULIA_CMD --sysimage "/vindicta/Vindicta.so" -e "using VindictaInteractive"
CMD $JULIA_CMD --sysimage Vindicta.so
