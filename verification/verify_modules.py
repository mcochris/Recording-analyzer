#!/usr/bin/env python3

import importlib.util
import sys

REQUIRED_MODULES = ["soundfile", "numpy", "argparse", "sys", "os"]

def check_modules(modules):
    missing = []
    for module in modules:
        if importlib.util.find_spec(module) is None:
            missing.append(module)
    return missing

missing = check_modules(REQUIRED_MODULES)

if not missing:
    print("true")
else:
    for name in missing:
        print(name)