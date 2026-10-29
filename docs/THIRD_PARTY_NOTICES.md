# Third-party notices

Fleet Comms source is MIT licensed. That license does not replace upstream licenses.
The Xcode project pins FluidAudio **0.17.7**, ONNX Runtime’s Swift package **1.24.2**, and Sparkle **2.10.1**.

## Libraries linked by the app

| Component | License | Retained notices |
| --- | --- | --- |
| [FluidAudio 0.17.7](https://github.com/FluidInference/FluidAudio/tree/0.17.7) | Apache-2.0 | [Full license](licenses/FluidAudio-LICENSE), [upstream third-party notices](licenses/FluidAudio-third-party/) |
| [ONNX Runtime 1.24.2](https://github.com/microsoft/onnxruntime-swift-package-manager/tree/v1.24.2) | MIT | [Full license and Microsoft copyright](licenses/ONNXRuntime-LICENSE) |
| [Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/tree/2.10.1) | MIT; bundled components BSD / MIT / zlib | [Full license and bundled component notices](licenses/Sparkle-LICENSE) |
| fastcluster (through FluidAudio) | BSD-2-Clause | [Copyright, terms and disclaimer](licenses/FluidAudio-third-party/fastcluster-LICENSE.md) |
| NeMo text processing (through FluidAudio) | Apache-2.0; upstream components MIT / Apache-2.0 | [Upstream component notice](licenses/FluidAudio-third-party/NemoTextProcessing-LICENSE.md) |

The `FluidAudio-third-party` directory preserves all notices supplied by the pinned library,
including optional language frontends, VBx, and Kokoro Core ML conversion provenance. Some cover library
capabilities Fleet Comms does not expose. These texts are copied without modification from the resolved
upstream package. The NeMo notice labels its component v0.3.0; the package manifest fetches v0.3.1.

## Downloaded models

Model weights are **not checked into this repository**. They download separately, on request or first use,
from the sources selected by `LocalModel` and `ModelPins`. Settings → Models displays sources and app-provided license labels.
FluidInference supplies Core ML conversions; the original model authors retain their rights.

| Model | Authors / source | License |
| --- | --- | --- |
| Silero VAD | [Silero](https://github.com/snakers4/silero-vad); [Core ML conversion](https://huggingface.co/FluidInference/silero-vad-coreml) | MIT |
| Parakeet Realtime EOU 120M | [NVIDIA](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1); [Core ML conversion](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) | [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/) |
| Parakeet TDT 0.6B v2 | [NVIDIA](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2); [Core ML conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml) | CC-BY-4.0 |
| Kokoro 82M | [hexgrad](https://huggingface.co/hexgrad/Kokoro-82M); [Core ML conversion](https://huggingface.co/FluidInference/kokoro-82m-coreml) | Apache-2.0; retain the conversion’s [notices](licenses/FluidAudio-third-party/KokoroANE-v3/NOTICE) and licenses when distributing adapted artifacts |
| Smart Turn v3.2 | [Pipecat](https://github.com/pipecat-ai/smart-turn); [model](https://huggingface.co/pipecat-ai/smart-turn-v3) | BSD-2-Clause |
| Fluid Speech Pro (optional, external) | FluidVoice / FluidInference, Parakeet fine-tune | CC-BY-4.0 as declared by the app; installed and licensed separately by FluidVoice, read in place only |

For CC-BY-4.0 models, preserve attribution to NVIDIA and FluidInference, the model’s source and
[license](https://creativecommons.org/licenses/by/4.0/), and identify any modifications when redistributing.
Check the exact downloaded revision’s model card and accompanying files before redistributing weights.
Fleet Comms does not download, modify, or remove Fluid Speech Pro.

## Distributing a build

Include these notices and the applicable full license texts with any binary distribution, together with
any additional notices accompanying the exact model revisions you distribute. Models downloaded later
retain their own terms. Source preparation does not certify a future binary or model redistribution.
