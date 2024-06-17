#/usr/bin/env bash
set -exo pipefail
unset HISTFILE
. ../_helpers.bash
ARCH=$([[ $(arch) == "arm64" ]] && echo "arm64" || echo "amd64")
LATEST_VERSION=$(curl -sL https://api.github.com/repos/veertuinc/anklet/releases/latest | jq -r ".tag_name")
curl -L -O https://github.com/veertuinc/anklet/releases/download/${LATEST_VERSION}/anklet_${LATEST_VERSION}_darwin_${ARCH}.zip
unzip anklet_${LATEST_VERSION}_darwin_${ARCH}.zip
chmod +x anklet_${LATEST_VERSION}_darwin_${ARCH}
cp anklet_${LATEST_VERSION}_darwin_${ARCH} /usr/local/bin/anklet
mkdir -p ~/.config/
sudo chown -R $AWS_INSTANCE_USER:staff ~/.config
cd ~/.config/
git clone --no-checkout --depth=1 --filter=blob:none https://github.com/veertuinc/anklet.git
pushd anklet
  git reset -q -- \
    plugins
  git checkout-index -a -f
popd
