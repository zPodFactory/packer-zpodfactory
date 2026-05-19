#!/bin/sh

rm -rf output-zpodfactory*

packer build \
    --var-file="zpodfactory-builder.json" \
    --var-file="zpodfactory-vars.json" \
    zpodfactory.json

chmod 644 output-zpodfactory/zpodfactory.ova
