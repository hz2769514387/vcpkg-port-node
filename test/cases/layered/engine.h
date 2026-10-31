// A static library that embeds Node.js privately.
//
// This is the shape most real projects end up with: a library owns the runtime and everything
// it drags in, and the applications on top of it never mention Node.js at all.
//
// It only works because the port's CMake config puts the whole link line on its INTERFACE:
// everything a consumer needs - the archives, the shared dependencies, the system libraries,
// the C++ standard, the stack size - travels with the imported target. When that is true, a
// static library linking the port PRIVATE still propagates all of it to whoever links the
// library, because CMake records PRIVATE dependencies of a static library as LINK_ONLY
// interface entries. When it is not true, the failure appears in the application's link, far
// away from the cause - which is why this scenario is worth a test rather than an assumption.
#ifndef EMBEDDING_ENGINE_ENGINE_H_
#define EMBEDDING_ENGINE_ENGINE_H_

#include <string>

namespace engine {

// Runs a JavaScript file in an embedded Node.js runtime, and returns the exit code the
// script asked for.
int RunScriptFile(const std::string& path);

// The versions of the runtime this library was linked against, so an application can print
// something it did not have to know anything about.
std::string RuntimeVersions();

}  // namespace engine

#endif  // EMBEDDING_ENGINE_ENGINE_H_
