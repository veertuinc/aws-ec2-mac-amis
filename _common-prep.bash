GETTING_STARTED_LOCATION="$HOME/getting-started"
# POPULATE .zshrc
[[ -z "$(grep "alias ll" ~/.zshrc)" ]] && echo "alias ll=\"ls -laht\"" >> $HOME/.zshrc
# Ensure the query tool exists
[[ ! -e "/usr/local/bin/ec2-metadata" ]] && curl http://s3.amazonaws.com/ec2metadata/ec2-metadata -o /usr/local/bin/ec2-metadata && chmod +x /usr/local/bin/ec2-metadata
# Install Anka
if [[ ! -d "$HOME/getting-started" ]]; then
  pushd $HOME
    git clone https://github.com/veertuinc/getting-started.git
  popd
fi
pushd $GETTING_STARTED_LOCATION
git pull
ANKA_LICENSE=${ANKA_LICENSE:-""}
[[ -z $(command -v anka) ]] && ./install-anka-virtualization-on-mac.bash
popd