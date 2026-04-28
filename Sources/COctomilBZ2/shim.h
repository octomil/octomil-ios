#ifndef COCTOMIL_BZ2_SHIM_H
#define COCTOMIL_BZ2_SHIM_H

// Wrapper for libbz2's public ``bzlib.h`` so SwiftPM can expose
// the streaming bz2 API to Swift code as ``import COctomilBZ2``.
//
// Both macOS and iOS SDKs ship ``bzlib.h`` (under ``usr/include``)
// and ``libbz2.tbd`` (under ``usr/lib``); the system module map
// next to this header pulls them in.

#include <bzlib.h>

#endif // COCTOMIL_BZ2_SHIM_H
