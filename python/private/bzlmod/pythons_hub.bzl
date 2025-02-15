# Copyright 2023 The Bazel Authors. All rights reserved
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"Repo rule used by bzlmod extension to create a repo that has a map of Python interpreters and their labels"

load("//python:versions.bzl", "WINDOWS_NAME")
load("//python/private:full_version.bzl", "full_version")
load(
    "//python/private:toolchains_repo.bzl",
    "get_host_os_arch",
    "get_host_platform",
    "get_repository_name",
    "python_toolchain_build_file_content",
)

def _have_same_length(*lists):
    if not lists:
        fail("expected at least one list")
    return len({len(length): None for length in lists}) == 1

_HUB_BUILD_FILE_TEMPLATE = """\
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

bzl_library(
    name = "interpreters_bzl",
    srcs = ["interpreters.bzl"],
    visibility = ["@rules_python//:__subpackages__"],
)

{toolchains}
"""

def _hub_build_file_content(
        prefixes,
        python_versions,
        set_python_version_constraints,
        user_repository_names,
        workspace_location):
    """This macro iterates over each of the lists and returns the toolchain content.

    python_toolchain_build_file_content is called to generate each of the toolchain
    definitions.
    """

    if not _have_same_length(python_versions, set_python_version_constraints, user_repository_names):
        fail("all lists must have the same length")

    rules_python = get_repository_name(workspace_location)

    # Iterate over the length of python_versions and call
    # build the toolchain content by calling python_toolchain_build_file_content
    toolchains = "\n".join([python_toolchain_build_file_content(
        prefix = prefixes[i],
        python_version = full_version(python_versions[i]),
        set_python_version_constraint = set_python_version_constraints[i],
        user_repository_name = user_repository_names[i],
        rules_python = rules_python,
    ) for i in range(len(python_versions))])

    return _HUB_BUILD_FILE_TEMPLATE.format(toolchains = toolchains)

_interpreters_bzl_template = """
INTERPRETER_LABELS = {{
{interpreter_labels}
}}
DEFAULT_PYTHON_VERSION = "{default_python_version}"
"""

_line_for_hub_template = """\
    "{key}": Label("@{name}_{platform}//:{path}"),
"""

def _hub_repo_impl(rctx):
    # Create the various toolchain definitions and
    # write them to the BUILD file.
    rctx.file(
        "BUILD.bazel",
        _hub_build_file_content(
            rctx.attr.toolchain_prefixes,
            rctx.attr.toolchain_python_versions,
            rctx.attr.toolchain_set_python_version_constraints,
            rctx.attr.toolchain_user_repository_names,
            rctx.attr._rules_python_workspace,
        ),
        executable = False,
    )

    (os, arch) = get_host_os_arch(rctx)
    platform = get_host_platform(os, arch)
    is_windows = (os == WINDOWS_NAME)
    path = "python.exe" if is_windows else "bin/python3"

    # Create a dict that is later used to create
    # a symlink to a interpreter.
    interpreter_labels = "".join([
        _line_for_hub_template.format(
            key = name + ("" if platform_str != "host" else "_host"),
            name = name,
            platform = platform_str,
            path = p,
        )
        for name in rctx.attr.toolchain_user_repository_names
        for platform_str, p in {
            # NOTE @aignas 2023-12-21: maintaining the `platform` specific key
            # here may be unneeded in the long term, but I am not sure if there
            # are other users that depend on it.
            platform: path,
            "host": "python",
        }.items()
    ])

    rctx.file(
        "interpreters.bzl",
        _interpreters_bzl_template.format(
            interpreter_labels = interpreter_labels,
            default_python_version = rctx.attr.default_python_version,
        ),
        executable = False,
    )

hub_repo = repository_rule(
    doc = """\
This private rule create a repo with a BUILD file that contains a map of interpreter names
and the labels to said interpreters. This map is used to by the interpreter hub extension.
This rule also writes out the various toolchains for the different Python versions.
""",
    implementation = _hub_repo_impl,
    attrs = {
        "default_python_version": attr.string(
            doc = "Default Python version for the build.",
            mandatory = True,
        ),
        "toolchain_prefixes": attr.string_list(
            doc = "List prefixed for the toolchains",
            mandatory = True,
        ),
        "toolchain_python_versions": attr.string_list(
            doc = "List of Python versions for the toolchains",
            mandatory = True,
        ),
        "toolchain_set_python_version_constraints": attr.string_list(
            doc = "List of version contraints for the toolchains",
            mandatory = True,
        ),
        "toolchain_user_repository_names": attr.string_list(
            doc = "List of the user repo names for the toolchains",
            mandatory = True,
        ),
        "_rules_python_workspace": attr.label(default = Label("//:does_not_matter_what_this_name_is")),
    },
)
