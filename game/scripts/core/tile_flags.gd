# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Per-tile service bits stored in the city's flags layer.
class_name TileFlags
extends RefCounted

const CONDUCTS_POWER := 0x80   ## part of the electrical network (lines, buildings)
const POWERED := 0x40          ## received power in the last distribution pass
const CONDUCTS_WATER := 0x20   ## part of the water network (pipes, buildings)
const WATERED := 0x10          ## received water in the last distribution pass
const SALT_WATER := 0x08       ## water tile is brackish; pumps here need a desalination plant
const LANDMARK := 0x04         ## protected from automatic redevelopment
const RESERVED_A := 0x02
const RESERVED_B := 0x01
