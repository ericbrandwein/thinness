# Use an official Python runtime as the base image
FROM archlinux

WORKDIR /thinness-sage

# Install packages
RUN pacman -Syu --noconfirm sagemath python-pipenv gcc

# Install pipenv dependencies
RUN --mount=type=bind,source=.,target=. pipenv --site-packages install 

# Specify the command to run when the container starts
CMD [ "bash" ]