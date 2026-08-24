#!/bin/sh

ansible-playbook \
        -i inventory/inventory_dev.yml \
        -l dev \
        --vault-password-file=../.vault-pass \
        playbooks/team_onboarding.yml

