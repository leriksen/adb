#!/usr/bin/env bash

set -euo pipefail

sudo pip3 install --upgrade --disable-pip-version-check pip==9.0.3
sudo pip3 install --upgrade --disable-pip-version-check setuptools
sudo pip3 install --upgrade --disable-pip-version-check databricks-cli

echo "python     == $(python --version)"
echo "pip3       == $(pip3 --version)"
echo "databricks == $(databricks --version)"