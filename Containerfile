FROM localhost/ros2-fedora:latest

ARG ROS2_DISTRO=humble

RUN dnf install -y \
  libcurl-devel \
  protobuf-devel \
  proj-devel \
  python3.12-pip \
  iproute \
  net-tools \
  openssh-clients \
  qt5-qtwayland-devel \
  qt6-qtwayland-devel \
  systemd \
  sudo \
  wget 


RUN python3.12 -m pip install \
  catkin_pkg \
  empy==3.3.4 \
  lark

RUN dnf update -y

#install curl 7.80.0
#RUN cd /opt && \
#wget https://curl.haxx.se/download/curl-7.80.0.tar.gz && \
#tar xzf curl-7.80.0.tar.gz && \
#cd curl-7.80.0 && \
#./configure --prefix=/usr/local --with-ssl && \
#make -j ${nproc} && \
#make install && \
#ldconfig && \
#cd .. && \
#rm -r curl-7.80.0 && \
#rm curl-7.80.0.tar.gz

#clone rail horizon
RUN cd /opt && \
git clone https://github.com/DSD-DBS/rail-horizon-oss

#clone all submodules
RUN cd /opt/rail-horizon-oss && \
git submodule sync --recursive && \
git submodule update --init --force --recursive 

#Patch here-olp-sdk gcc-13+ compile issues
RUN cd /opt/rail-horizon-oss/submodules/internal/map-service/externals/here-olp-sdk && \
git checkout v1.19.0

#Patch map-service gcc-13+ compile issues
ADD 0001-Resolve-compile-issues-with-gcc-13.patch /opt/rail-horizon-oss/
RUN cd /opt/rail-horizon-oss/submodules/internal/map-service && \
git apply /opt/rail-horizon-oss/0001-Resolve-compile-issues-with-gcc-13.patch

#set rail horizon environment
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp
ENV PERSISTENT_STORAGE_ROOT_DIR=/opt/rail-horizon-oss/documents/maps
ENV DB_MAP_VERSION=63
ENV DB_MAP_ENDPOINT=DBMC
ENV DB_MAP_CATALOG=validate.s4r2.oss.4

RUN echo "RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION}" >> /etc/environment
RUN echo "PERSISTENT_STORAGE_ROOT_DIR=${PERSISTENT_STORAGE_ROOT_DIR}" >> /etc/environment
RUN echo "DB_MAP_VERSION=${DB_MAP_VERSION}" >> /etc/environment
RUN echo "DB_MAP_ENDPOINT=${DB_MAP_ENDPOINT}" >> /etc/environment
RUN echo "DB_MAP_CATALOG=${DB_MAP_CATALOG}" >> /etc/environment


#build rail horizon
RUN cd /opt/rail-horizon-oss && \
source /opt/ros/${ROS2_DISTRO}/install/setup.bash && \
colcon build --base-paths src \ 
--cmake-args -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
--event-handlers console_cohesion+ --packages-up-to dsd_rail_horizon

ADD rail-horizon.service /lib/systemd/system
ADD rail-horizon-position-spoofing.service /lib/systemd/system

RUN systemctl enable rail-horizon.service
RUN systemctl enable rail-horizon-position-spoofing.service

ARG USERNAME=railhorizon
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME
##    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
##    && chmod 0440 /etc/sudoers.d/$USERNAME

RUN echo "${USERNAME}:pass" | chpasswd

CMD [ "/usr/sbin/init" ]
