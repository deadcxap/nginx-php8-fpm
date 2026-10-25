#!/usr/bin/env python3
"""Exercise publication gates without contacting a registry."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "ghcr.io/example/project"
TAGS = {
    "with-node": "nginx1.28.0_php8.5.2_node25.6.0",
    "without-node": "nginx1.28.0_php8.5.2",
}
MOVING_TAGS = {f"{REPOSITORY}:latest", f"{REPOSITORY}:latest-without-node"}


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="publish-check-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.archives = self.directory / "archives"
        self.archives.mkdir()
        self.log = self.directory / "docker.jsonl"
        self.summary = self.directory / "summary.md"
        for variant, tag in TAGS.items():
            for arch in ("amd64", "arm64"):
                self.artifact(variant, arch, "tar").write_bytes(b"test archive")
                self.artifact(variant, arch, "tag").write_text(tag + "\n")

        mock_bin = self.directory / "bin"
        mock_bin.mkdir()
        docker = mock_bin / "docker"
        docker.write_text('''#!/usr/bin/env python3
import json
import os
import sys

command = sys.argv[1:]
with open(os.environ["MOCK_DOCKER_LOG"], "a") as log:
    log.write(json.dumps(command) + "\\n")
if command[0] == "push" and command[1] == os.environ.get("MOCK_FAIL_REFERENCE"):
    sys.exit(1)
if command[:3] == ["buildx", "imagetools", "create"]:
    if command[4] == os.environ.get("MOCK_FAIL_REFERENCE"):
        sys.exit(1)
elif command[:2] == ["image", "inspect"]:
    arch = command[-1].rsplit("-", 1)[1]
    if command[-1] == os.environ.get("MOCK_WRONG_PLATFORM"):
        arch = "s390x"
    print("linux/" + arch)
elif command[0] not in ("load", "tag", "push"):
    raise SystemExit("Unexpected Docker operation: " + repr(command))
''')
        docker.chmod(0o755)
        self.environment = {
            **os.environ,
            "PATH": str(mock_bin) + os.pathsep + os.environ["PATH"],
            "REPOSITORY": "Example/Project",
            "MOCK_DOCKER_LOG": str(self.log),
            "GITHUB_STEP_SUMMARY": str(self.summary),
        }

    def artifact(self, variant, arch, extension):
        return self.archives / f"image-{variant}-{arch}.{extension}"

    def publish(self, **environment):
        self.log.write_text("")
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/publish-images.sh"), str(self.archives)],
            env={**self.environment, **environment},
            text=True,
            capture_output=True,
        )
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, calls

    def test_versions_identify_the_correct_images_and_manifests(self):
        result, calls = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        tagged = {call[2]: call[1] for call in calls if call[0] == "tag"}
        pushed = {call[1] for call in calls if call[0] == "push"}
        manifests = {
            call[4]: call[5:] for call in calls
            if call[:3] == ["buildx", "imagetools", "create"]
        }
        for variant, tag in TAGS.items():
            references = [f"{REPOSITORY}:{tag}-{arch}" for arch in ("amd64", "arm64")]
            self.assertEqual(manifests[f"{REPOSITORY}:{tag}"], references)
            for arch, reference in zip(("amd64", "arm64"), references):
                self.assertEqual(tagged[reference], f"local/nginx-php8-fpm:{variant}-{arch}")
                self.assertIn(reference, pushed)
        self.assertEqual(len(pushed), 4)
        self.assertEqual(len(manifests), 4)
        self.assertEqual(manifests[f"{REPOSITORY}:latest"], [f"{REPOSITORY}:{TAGS['with-node']}"])
        self.assertEqual(manifests[f"{REPOSITORY}:latest-without-node"], [f"{REPOSITORY}:{TAGS['without-node']}"])
        published_manifests = list(manifests)
        self.assertEqual(set(published_manifests[-2:]), MOVING_TAGS)
        self.assertIn(TAGS["with-node"], self.summary.read_text())
        self.assertIn(TAGS["without-node"], self.summary.read_text())
        self.assertFalse(any("build-" in argument for call in calls for argument in call))

    def test_missing_artifacts_abort_before_docker_operations(self):
        for extension in ("tar", "tag"):
            with self.subTest(extension=extension):
                artifact = self.artifact("without-node", "arm64", extension)
                content = artifact.read_bytes()
                artifact.unlink()
                result, calls = self.publish()
                artifact.write_bytes(content)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Missing image archive or version tag", result.stderr)
                self.assertEqual(calls, [])

    def test_invalid_or_inconsistent_versions_abort_before_docker_operations(self):
        for tag in (
            "nginx1.28.0_php8.5.2_node25.6.0",  # Wrong variant.
            "nginx1.29.0_php8.5.2",  # Different version on arm64.
            "nginx1.28.0_php8.5.2\nunexpected-output",
            "nginx1.28.0_php8.5.2-RC1",
            "",
        ):
            with self.subTest(tag=tag):
                self.artifact("without-node", "arm64", "tag").write_text(tag + "\n")
                result, calls = self.publish()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])

    def test_wrong_platform_aborts_before_any_publication(self):
        result, calls = self.publish(MOCK_WRONG_PLATFORM="local/nginx-php8-fpm:without-node-arm64")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unexpected platform", result.stderr)
        self.assertFalse(any(call[0] in ("tag", "push", "buildx") for call in calls))

    def test_failed_push_or_version_manifest_does_not_update_moving_tags(self):
        for tag in (TAGS["without-node"] + "-arm64", TAGS["without-node"]):
            with self.subTest(tag=tag):
                result, calls = self.publish(MOCK_FAIL_REFERENCE=f"{REPOSITORY}:{tag}")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(argument in MOVING_TAGS for call in calls for argument in call))


if __name__ == "__main__":
    unittest.main()
