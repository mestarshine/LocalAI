ARG GO_VERSION=1.20

FROM golang:$GO_VERSION as requirements

ARG BUILD_TYPE
ARG CUDA_MAJOR_VERSION=11
ARG CUDA_MINOR_VERSION=7

ENV BUILD_TYPE=${BUILD_TYPE}

RUN apt-get update && \
    apt-get install -y ca-certificates cmake curl

# CuBLAS requirements
RUN if [ "${BUILD_TYPE}" = "cublas" ]; then \
    apt-get install -y software-properties-common && \
    apt-add-repository contrib && \
    curl -O https://developer.download.nvidia.com/compute/cuda/repos/debian11/x86_64/cuda-keyring_1.0-1_all.deb && \
    dpkg -i cuda-keyring_1.0-1_all.deb && \
    rm -f cuda-keyring_1.0-1_all.deb && \
    apt-get update && \
    apt-get install -y cuda-nvcc-${CUDA_MAJOR_VERSION}-${CUDA_MINOR_VERSION} libcublas-dev-${CUDA_MAJOR_VERSION}-${CUDA_MINOR_VERSION} \
    ; fi
ENV PATH /usr/local/cuda/bin:${PATH}

# OpenBLAS requirements
RUN apt-get install -y libopenblas-dev

# Stable Diffusion requirements
RUN apt-get install -y libopencv-dev && \
    ln -s /usr/include/opencv4/opencv2 /usr/include/opencv2

FROM requirements as builder

ARG GO_TAGS=stablediffusion

ENV GO_TAGS=${GO_TAGS}
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_REQUIRE_CUDA="cuda>=${CUDA_MAJOR_VERSION}.0"
ENV NVIDIA_VISIBLE_DEVICES=all

WORKDIR /build

COPY Makefile .
RUN make get-sources
COPY go.mod .
RUN make prepare
COPY . .
RUN make build

FROM requirements

ARG FFMPEG

ENV REBUILD=true
ENV HEALTHCHECK_ENDPOINT=http://localhost:8080/readyz

# Add FFmpeg
RUN if [ "${FFMPEG}" = "true" ]; then \
    apt-get install -y ffmpeg \
    ; fi

WORKDIR /build

COPY --from=builder /build/local-ai ./
COPY entrypoint.sh .

# Define the health check command
HEALTHCHECK --interval=1m --timeout=10m --retries=10 \
  CMD curl -f $HEALTHCHECK_ENDPOINT || exit 1

EXPOSE 8080
ENTRYPOINT [ "/build/entrypoint.sh" ]
