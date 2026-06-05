import Foundation

/// Builds an in-memory layer tree from flat PSD layer records (index 0 = stack bottom).
enum LayerTreeBuilder {
    static func build(
        records: [LayerRecord],
        into root: GroupLayer,
        collector: inout CompatibilityIssueCollector,
        makePixelLayer: (LayerRecord, inout CompatibilityIssueCollector) throws -> PixelLayer?
    ) throws {
        var openGroups: [GroupLayer] = []
        var current = root

        for record in records {
            if let kind = LayerExtra.sectionDividerKind(for: record) {
                try handleSectionDivider(
                    kind,
                    record: record,
                    openGroups: &openGroups,
                    current: &current
                )
                continue
            }

            let layerName = record.name.isEmpty ? "Layer" : record.name
            if let kindLabel = LayerExtra.explicitUnsupportedLayerKindLabel(for: record) {
                collector.recordDroppedUnsupportedLayer(layerName: layerName, kindLabel: kindLabel)
                continue
            }
            if LayerExtra.shouldSilentlySkipLayerRecord(record) {
                continue
            }
            if let kindLabel = LayerExtra.droppedLayerKindLabel(for: record) {
                collector.recordDroppedUnsupportedLayer(layerName: layerName, kindLabel: kindLabel)
                continue
            }
            guard let pixel = try makePixelLayer(record, &collector) else {
                if record.width > 0, record.height > 0 {
                    collector.recordDroppedUnsupportedLayer(layerName: layerName, kindLabel: "non-pixel")
                }
                continue
            }
            current.append(pixel)
        }

        guard openGroups.isEmpty else {
            throw PSDError.corruptStructure("unclosed layer group section divider")
        }
    }

    private static func handleSectionDivider(
        _ kind: LayerExtra.SectionDividerKind,
        record: LayerRecord,
        openGroups: inout [GroupLayer],
        current: inout GroupLayer
    ) throws {
        let name = record.name.isEmpty ? "Group" : record.name
        switch kind {
        case .bounding:
            let group = GroupLayer(
                name: name,
                isVisible: record.flags.visible,
                opacity: record.opacity,
                blendMode: record.blendMode == .passThrough ? .passThrough : record.blendMode
            )
            current.append(group)
            openGroups.append(group)
            current = group
        case .openFolder, .closedFolder:
            guard let group = openGroups.popLast() else {
                throw PSDError.corruptStructure("section divider folder end without matching group start")
            }
            guard group.name == name else {
                throw PSDError.corruptStructure(
                    "section divider group name mismatch: '\(group.name)' vs '\(name)'"
                )
            }
            guard let parent = group.parent else {
                throw PSDError.corruptStructure("section divider group has no parent")
            }
            current = parent
        }
    }
}

// MARK: - Write flattening (semantic save)

/// Flattens an in-memory layer tree into PSD layer records (index 0 = stack bottom).
enum LayerTreeFlattener {
    static func containsGroupLayers(in group: GroupLayer) -> Bool {
        group.children.contains { $0 is GroupLayer }
    }

    /// Pixel layers in the same depth-first order as `flatten`.
    static func collectPixels(in group: GroupLayer) -> [PixelLayer] {
        var pixels: [PixelLayer] = []
        collectPixels(in: group, into: &pixels)
        return pixels
    }

    /// Emits layer records for `group`'s children only; the container itself is not written.
    static func flatten(
        group: GroupLayer,
        makePixelRecord: (PixelLayer) throws -> LayerRecord,
        makeSectionRecord: (GroupLayer, LayerExtra.SectionDividerKind) throws -> LayerRecord
    ) throws -> [LayerRecord] {
        var records: [LayerRecord] = []
        try appendFlattened(
            childrenOf: group,
            into: &records,
            makePixelRecord: makePixelRecord,
            makeSectionRecord: makeSectionRecord
        )
        return records
    }

    private static func collectPixels(in group: GroupLayer, into pixels: inout [PixelLayer]) {
        for child in group.children {
            if let pixel = child as? PixelLayer {
                pixels.append(pixel)
            } else if let nested = child as? GroupLayer {
                collectPixels(in: nested, into: &pixels)
            }
        }
    }

    private static func appendFlattened(
        childrenOf group: GroupLayer,
        into records: inout [LayerRecord],
        makePixelRecord: (PixelLayer) throws -> LayerRecord,
        makeSectionRecord: (GroupLayer, LayerExtra.SectionDividerKind) throws -> LayerRecord
    ) throws {
        for child in group.children {
            if let pixel = child as? PixelLayer {
                records.append(try makePixelRecord(pixel))
            } else if let nested = child as? GroupLayer {
                records.append(try makeSectionRecord(nested, .bounding))
                try appendFlattened(
                    childrenOf: nested,
                    into: &records,
                    makePixelRecord: makePixelRecord,
                    makeSectionRecord: makeSectionRecord
                )
                records.append(try makeSectionRecord(nested, .openFolder))
            }
        }
    }
}
