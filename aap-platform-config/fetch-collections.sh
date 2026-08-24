#!/bin/sh


### PAH/Galaxy server tokens
source ../secrets_tokens_env.sh

### Fect collection
ansible-galaxy collection install -r collections/requirements.yml  -p ./collections --force  --clear-response-cache
