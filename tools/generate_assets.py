#!/usr/bin/env python3
"""Generate Umbra's parallax background layers with the Gemini image API.

Run this on your own machine. Your API key is read from the environment and is
never written to disk or committed:

    export GEMINI_API_KEY="your-key-here"
    python3 tools/generate_assets.py --list-models      # check what your key can use
    python3 tools/generate_assets.py                    # generate everything
    python3 tools/generate_assets.py --only mid_ruins   # regenerate one layer

Output goes to assets/images/, which is what pubspec.yaml ships to the app.

IMPORTANT: model names on this API change often, and this script was written
without being able to reach the API to verify them. Run --list-models first and
set MODEL below to whatever image-capable model your key actually returns.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API_ROOT = "https://generativelanguage.googleapis.com/v1beta"

# Verify against --list-models before trusting this.
MODEL = "gemini-2.5-flash-image"

OUTPUT_DIR = os.path.join("assets", "images")

# --------------------------------------------------------------------------
# The art direction.
#
# Every prompt shares STYLE so the layers look like one world rather than five
# unrelated pictures. Layers are ordered far -> near, and get darker and less
# detailed as they approach the camera. That ordering is the whole trick: depth
# reads as *contrast falloff*, not as detail.
#
# Deliberately original environments. Do not prompt for another game's
# characters or specific landmarks.
# --------------------------------------------------------------------------

STYLE = (
    "monochrome greyscale only, no colour whatsoever, hand-painted "
    "atmospheric 2D game background, soft volumetric fog, heavy aerial "
    "perspective, film grain, subtle vignette, painterly not photographic, "
    "no text, no watermark, no characters, no creatures, no user interface, "
    "horizontal 16:9 side-scrolling game backdrop"
)

LAYERS: dict[str, str] = {
    # Furthest: almost white. Sets the light source.
    "far_sky": (
        "An empty pale sky of drifting mist, near-white at the horizon fading "
        "to light grey above. A single diffuse cold light source glowing "
        "behind the fog. Utterly minimal, almost abstract, no ground, no "
        "objects. Extremely low contrast."
    ),
    # Distant landforms, still very light.
    "far_ridge": (
        "Distant jagged rock spires and eroded cliff formations seen through "
        "thick haze, rendered as flat pale grey silhouettes with no interior "
        "detail. Softened edges, washed out by atmosphere. Lower third empty "
        "so nearer layers can overlap it."
    ),
    # Mid: the storytelling layer. This is where "more advanced than Limbo" lives.
    "mid_ruins": (
        "Mid-distance silhouette of a collapsed industrial structure half "
        "swallowed by dead forest: broken scaffolding, a leaning water tower, "
        "snapped steel cables, bare crooked trees. Medium grey, flat "
        "silhouette shapes, some depth separation between the nearest and "
        "furthest elements. Moody and desolate."
    ),
    # Near: dark, simple shapes.
    "near_trees": (
        "Near-distance dead trees and tangled bare branches as dark charcoal "
        "silhouettes against fog, thin trunks, sparse and irregular spacing. "
        "Almost no interior detail. Slight motion blur."
    ),
    # Foreground: nearly black, heavily blurred. Sells the depth of field.
    "fore_growth": (
        "Extreme foreground of tall wild grass, reeds and a few low branches, "
        "pure black silhouette, heavily out of focus with a strong bokeh "
        "blur, occupying only the bottom edge of the frame. The upper two "
        "thirds must be completely empty and transparent-looking flat black."
    ),
}


def build_prompt(description: str) -> str:
    return f"{description} Style: {STYLE}."


def request_image(prompt: str, api_key: str) -> bytes:
    """Ask the API for one image and return its raw bytes."""
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        # Ask for an image back rather than a description of one.
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }
    request = urllib.request.Request(
        f"{API_ROOT}/models/{MODEL}:generateContent",
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            # Header auth, so the key never lands in a URL, a shell history
            # entry, or a proxy access log.
            "x-goog-api-key": api_key,
        },
        method="POST",
    )

    with urllib.request.urlopen(request, timeout=180) as response:
        body = json.load(response)

    # Walk the response for the first inline image blob.
    for candidate in body.get("candidates", []):
        for part in candidate.get("content", {}).get("parts", []):
            blob = part.get("inlineData") or part.get("inline_data")
            if blob and blob.get("data"):
                return base64.b64decode(blob["data"])

    raise RuntimeError(
        "No image in the response. The model may not support image output.\n"
        f"{json.dumps(body)[:800]}"
    )


def list_models(api_key: str) -> None:
    request = urllib.request.Request(
        f"{API_ROOT}/models",
        headers={"x-goog-api-key": api_key},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        body = json.load(response)

    print("Models your key can reach:\n")
    for model in body.get("models", []):
        name = model.get("name", "").removeprefix("models/")
        methods = ",".join(model.get("supportedGenerationMethods", []))
        print(f"  {name:<45} {methods}")
    print("\nPick an image-capable one and set MODEL at the top of this file.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--list-models",
        action="store_true",
        help="show the models this key can use, then exit",
    )
    parser.add_argument(
        "--only",
        metavar="LAYER",
        help=f"generate a single layer ({', '.join(LAYERS)})",
    )
    args = parser.parse_args()

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print(
            "GEMINI_API_KEY is not set.\n"
            '  export GEMINI_API_KEY="your-key-here"',
            file=sys.stderr,
        )
        return 1

    try:
        if args.list_models:
            list_models(api_key)
            return 0
    except urllib.error.HTTPError as error:
        print(
            f"HTTP {error.code}: {error.read().decode()[:500]}", file=sys.stderr
        )
        return 1

    if args.only and args.only not in LAYERS:
        print(
            f"Unknown layer {args.only!r}. Known: {', '.join(LAYERS)}",
            file=sys.stderr,
        )
        return 1

    wanted = {args.only: LAYERS[args.only]} if args.only else LAYERS
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    failures = 0
    for name, description in wanted.items():
        destination = os.path.join(OUTPUT_DIR, f"{name}.png")
        print(f"generating {name} ...", flush=True)
        try:
            image = request_image(build_prompt(description), api_key)
        except urllib.error.HTTPError as error:
            detail = error.read().decode()[:400]
            print(f"  FAILED  HTTP {error.code}: {detail}", file=sys.stderr)
            failures += 1
            continue
        except Exception as error:  # noqa: BLE001 - report and keep going
            print(f"  FAILED  {error}", file=sys.stderr)
            failures += 1
            continue

        with open(destination, "wb") as handle:
            handle.write(image)
        print(f"  wrote {destination} ({len(image) // 1024} KB)")

    if failures:
        print(f"\n{failures} layer(s) failed.", file=sys.stderr)
        return 1

    print(f"\nDone. Layers are in {OUTPUT_DIR}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
