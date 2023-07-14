FROM gitpod/workspace-postgres

RUN sudo apt-get update  && sudo apt-get install -y redis-server apt-transport-https ca-certificates && sudo update-ca-certificates  && sudo rm -rf /var/lib/apt/lists/*

USER gitpod
SHELL ["/bin/bash", "-c"]

RUN cd && rvm pkg install openssl && /home/gitpod/.rvm/bin/rvm install "ruby-3.0.6" --with-openssl-dir=$HOME/.rvm/usr

