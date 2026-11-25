#!/usr/bin/env python3
#** ******************************************************************************
# *
# * Licensed under the Apache License, Version 2.0 (the "License");
# * you may not use this file except in compliance with the License.
#** ******************************************************************************

import argparse
import importlib.util
import inspect
import os
import sys
import time
from pathlib import Path

import yaml


dir_path = os.path.dirname(os.path.realpath(__file__))
components_root = (Path(dir_path).resolve().parents[2] / "vts_hal_test_components").resolve()
DEFAULT_CONFIG_FILE = "vts_l3_test_setup.yaml"

sys.path.append(os.path.join(dir_path, "../"))
sys.path.append(os.path.join(dir_path, "../raft"))

try:
    from raft.framework.core.logModule import logModule
except ModuleNotFoundError:
    class logModule:
        INFO = 20

        def __init__(self, name=None, level=INFO):
            self.name = name or "L3Tests"

        def info(self, message):
            print(f"[INFO] {message}")

        def warn(self, message):
            print(f"[WARN] {message}")

        def error(self, message):
            print(f"[ERROR] {message}")


COMPONENT_ALIASES = {
    "deepsleep": "rdk-halif-test-deepsleep_manager",
    "deepsleep_manager": "rdk-halif-test-deepsleep_manager",
    "deepsleepmanager": "rdk-halif-test-deepsleep_manager",
    "rdk-halif-deepsleep_manager": "rdk-halif-test-deepsleep_manager",
    "rdk-halif-test-deepsleep_manager": "rdk-halif-test-deepsleep_manager",
}


def _resolve_component_dir(component):
    alias = COMPONENT_ALIASES.get((component or "").strip().lower(), component)
    candidates = [alias, component]
    normalized = component.replace("rdk-halif-test-", "").replace("rdk-halif-", "")
    candidates.extend([
        normalized,
        f"rdk-halif-test-{normalized}",
        f"rdk-halif-{normalized}",
        normalized.replace("_", "-"),
        normalized.replace("-", "_"),
    ])

    for candidate_name in candidates:
        if not candidate_name:
            continue
        candidate = (components_root / candidate_name).resolve()
        if candidate.is_dir():
            return candidate

    return (components_root / component).resolve()


def _load_python_module(py_file):
    parent = str(py_file.parent)
    if parent not in sys.path:
        sys.path.append(parent)

    module_name = f"vts_l3_{py_file.stem}_{abs(hash(str(py_file)))}"
    spec = importlib.util.spec_from_file_location(module_name, str(py_file))
    if spec is None or spec.loader is None:
        return None

    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        print(f"[L3Runner] Failed to import {py_file}: {exc}")
        return None
    return module


def _discover_test_classes(component_dir):
    tests_dir = (component_dir / "host/tests").resolve()
    if not tests_dir.is_dir():
        return tests_dir, {}

    class_map = {}
    for py_file in sorted(tests_dir.rglob("*.py")):
        if py_file.name.startswith("__"):
            continue

        module = _load_python_module(py_file)
        if module is None:
            continue

        for name, obj in inspect.getmembers(module, inspect.isclass):
            if name.startswith("_"):
                continue
            if obj.__module__ == module.__name__:
                class_map[name] = (obj, py_file)
                class_map[name.lower()] = (obj, py_file)

    return tests_dir, class_map


def run_test_instance(test_class, summary_log, component):
    test_class._menuConfigFile = str(Path(dir_path) / "vts_l3_test_setup.yaml")
    test_class._moduleName = "VTS"
    test_class._dirPath = dir_path
    test_class._profilePath = _resolve_component_dir(component)

    try:
        test_instance = test_class(summary_log)
    except Exception as exc:
        summary_log.error(f"Failed to instantiate {test_class.__name__}: {exc}")
        return False

    try:
        if hasattr(test_instance, "run") and callable(test_instance.run):
            result = test_instance.run(False)
        elif hasattr(test_instance, "testFunction") and callable(test_instance.testFunction):
            result = test_instance.testFunction()
        else:
            summary_log.warn(f"No runnable entrypoint found for {test_class.__name__}")
            return False
    except Exception as exc:
        summary_log.error(f"Failed during {test_class.__name__}: {exc}")
        return False

    time.sleep(2)
    return result is not False


def runL3TestInstances(summary_log, suite_config_path=None):
    config_path = (
        Path(suite_config_path).expanduser().resolve()
        if suite_config_path
        else (Path(dir_path) / DEFAULT_CONFIG_FILE).resolve()
    )

    if not config_path.is_file():
        summary_log.error(f"Config file not found: {config_path}")
        return False

    try:
        with config_path.open("r", encoding="utf-8") as config_file:
            data = yaml.safe_load(config_file) or {}
    except Exception as exc:
        summary_log.error(f"Failed to read config file {config_path}: {exc}")
        return False

    test_entries = data.get("L3Tests", {}).get("tests", [])
    if not test_entries:
        test_entries = data.get("nonAvL3Tests", {}).get("tests", [])

    if not isinstance(test_entries, list):
        summary_log.error("Invalid config format: L3Tests.tests must be a list")
        return False

    matched_any = False
    final_result = True

    for entry in test_entries:
        if not isinstance(entry, dict) or not entry.get("enabled", True):
            continue

        component = entry.get("module")
        requested_classes = entry.get("tests", [])
        if not component or not isinstance(requested_classes, list):
            summary_log.warn(f"Skipping invalid test entry: {entry}")
            continue

        component_dir = _resolve_component_dir(component)
        tests_dir, class_map = _discover_test_classes(component_dir)
        if not tests_dir.is_dir():
            summary_log.warn(f"Host tests directory not found for module '{component}': {tests_dir}")
            continue

        for class_name in requested_classes:
            match = class_map.get(class_name) or class_map.get(class_name.lower())
            if match is None:
                summary_log.warn(f"Class {class_name} not found under module '{component}' L3 host tests")
                continue

            test_class, module_file = match
            matched_any = True
            summary_log.info(f"Loading L3 test class {class_name} from {module_file}")
            final_result = run_test_instance(test_class, summary_log, component) and final_result

    if not matched_any:
        summary_log.error("No runnable L3 test class was discovered from the configured modules")
        return False

    return bool(final_result)


def _parse_cli_args():
    parser = argparse.ArgumentParser(description="Unified VTS L3 RAFT runner")
    parser.add_argument("--config", dest="config", default=None)
    parser.add_argument("--deviceConfig", dest="device_config", default=None)
    parser.add_argument("--suiteConfig", dest="suite_config", default=None)
    return parser.parse_args()


if __name__ == "__main__":
    cli_args = _parse_cli_args()
    summary_log = logModule("L3Tests", level=logModule.INFO)
    print(f"[L3Runner] Starting unified L3 runner config={cli_args.config} deviceConfig={cli_args.device_config}")
    result = runL3TestInstances(summary_log, cli_args.suite_config)
    print(f"[L3Runner] Completed with status={bool(result)}")
    raise SystemExit(0 if result else 1)
