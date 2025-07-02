FROM julia:1.11 AS base
RUN mkdir /planar \
    && apt-get update \
    && apt-get -y install sudo direnv git \
    && useradd -u 1000 -G sudo -U -m -s /bin/bash plnuser \
    && chown plnuser:plnuser /planar \
    # Allow sudoers
    && echo "plnuser ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers
WORKDIR /planar
USER plnuser
ARG CPU_TARGET=generic
ENV JULIA_BIN=/usr/local/julia/bin/julia
ARG JULIA_CMD="$JULIA_BIN -C $CPU_TARGET"
ENV JULIA_CMD=$JULIA_CMD
ENV JULIA_CPU_TARGET ${CPU_TARGET}

# PLANAR ENV VARS GO HERE
ENV PLANAR_LIQUIDATION_BUFFER=0.02
ENV JULIA_NOPRECOMP=""
ENV JULIA_PRECOMP=Remote,PaperMode,LiveMode,Fetch,Optimization,Plotting
CMD $JULIA_BIN -C $JULIA_CPU_TARGET