ARG FROM_IMAGE=gpuci/miniconda-cuda
ARG CUDA_VER=10.2
ARG LINUX_VER=ubuntu18.04
FROM ${FROM_IMAGE}:${CUDA_VER}-devel-${LINUX_VER}

# Required arguments
ARG RAPIDS_CHANNEL=rapidsai-nightly
ARG RAPIDS_VER=0.14
ARG PYTHON_VER=3.6

# Optional arguments
ARG BUILD_STACK_VER=7.5.0
ARG CCACHE_VERSION=master

# Capture argument used for FROM
ARG CUDA_VER

# Update environment for gcc/g++ builds
ENV CC=/usr/bin/gcc
ENV CXX=/usr/bin/g++
ENV CUDAHOSTCXX=/usr/bin/g++

# Enables "source activate conda"
SHELL ["/bin/bash", "-c"]

# Add a condarc for channels and override settings
RUN if [ "${RAPIDS_CHANNEL}" == "rapidsai" ] ; then \
      echo -e "\
ssl_verify: False \n\
channels: \n\
  - rapidsai \n\
  - conda-forge \n\
  - nvidia \n\
  - defaults \n" > /conda/.condarc \
      && cat /conda/.condarc ; \
    else \
      echo -e "\
ssl_verify: False \n\
channels: \n\
  - rapidsai \n\
  - rapidsai-nightly \n\
  - conda-forge \n\
  - nvidia \n\
  - defaults \n" > /conda/.condarc \
      && cat /conda/.condarc ; \
    fi

# Create `rapids` conda env and make default
RUN source activate base \
    && conda install -y --override-channels -c gpuci gpuci-tools

RUN gpuci_retry conda create --no-default-packages --override-channels -n rapids \
      -c nvidia \
      -c conda-forge \
      -c defaults \
      nomkl \
      cudatoolkit=${CUDA_VER} \
      git \
      libgcc-ng=${BUILD_STACK_VER} \
      libstdcxx-ng=${BUILD_STACK_VER} \
      python=${PYTHON_VER} \
    && sed -i 's/conda activate base/conda activate rapids/g' ~/.bashrc

# Create symlink for old scripts expecting `gdf` conda env
RUN ln -s /opt/conda/envs/rapids /opt/conda/envs/gdf

# Install build/doc/notebook env meta-pkgs
#
# Once installed remove the meta-pkg so dependencies can be freely updated &
# the meta-pkg can be installed again with updates
RUN gpuci_retry conda install -y -n rapids --freeze-installed \
      rapids-build-env=${RAPIDS_VER} \
      rapids-doc-env=${RAPIDS_VER} \
      rapids-notebook-env=${RAPIDS_VER} \
    && conda remove -y -n rapids --force-remove \
      rapids-build-env=${RAPIDS_VER} \
      rapids-doc-env=${RAPIDS_VER} \
      rapids-notebook-env=${RAPIDS_VER}

# Build ccache from source and create symlinks
RUN curl -s -L https://github.com/ccache/ccache/archive/master.zip -o /tmp/ccache-${CCACHE_VERSION}.zip \
    && unzip -d /tmp/ccache-${CCACHE_VERSION} /tmp/ccache-${CCACHE_VERSION}.zip \
    && cd /tmp/ccache-${CCACHE_VERSION}/ccache-master \
    && ./autogen.sh \
    && ./configure --disable-man --with-libb2-from-internet --with-libzstd-from-internet\
    && make install -j \
    && cd / \
    && rm -rf /tmp/ccache-${CCACHE_VERSION}* \
    && mkdir -p /ccache

# Setup ccache env vars
ENV CCACHE_NOHASHDIR=
ENV CCACHE_DIR="/ccache"
ENV CCACHE_COMPILERCHECK="%compiler% --version"

# Uncomment these env vars to force ccache to be enabled by default
#ENV CC="/usr/local/bin/gcc"
#ENV CXX="/usr/local/bin/g++"
#ENV NVCC="/usr/local/bin/nvcc"
#ENV CUDAHOSTCXX="/usr/local/bin/g++"
#RUN ln -s "$(which ccache)" "/usr/local/bin/gcc" \
#    && ln -s "$(which ccache)" "/usr/local/bin/g++" \
#    && ln -s "$(which ccache)" "/usr/local/bin/nvcc"

# Clean up pkgs to reduce image size and chmod for all users
RUN conda clean -afy \
    && chmod -R ugo+w /opt/conda /ccache

ENTRYPOINT [ "/usr/bin/tini", "--" ]
CMD [ "/bin/bash" ]