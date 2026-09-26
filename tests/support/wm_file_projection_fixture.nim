import std/options
import types/[core, session, wm_v1, wm_presentation]

proc fileProjectionRequest*(): ProjectionRequest =
  ProjectionRequest(
    connectionEpoch: 9,
    requestId: 12,
    sceneGeneration: 19,
    policyGeneration: 2,
    affectedOutputs: @[7'u64],
  )

proc fileProjection*(): PolicyProjection =
  let member = ProjectionTabMember(surfaceIndex: 0, surfaceGeneration: 1)
  result.activeOutput = 7
  result.outputs = @[
    PolicyOutputProjection(
      output: ProjectionOutput(output: 7, placementCount: 1, focusGeneration: 1),
      placements: @[
        ProjectionPlacement(
          surfaceIndex: 0,
          surfaceGeneration: 1,
          stateGeneration: 1,
          width: 640,
          height: 480,
          transform: 1,
        )
      ],
    )
  ]
  result.indicators =
    @[ProjectionIndicator(output: 7, slot: 1, indicator: 2, action: 11, labelLen: 1)]
  result.indicators[0].label[0] = byte('w')
  result.outputStatuses =
    @[ProjectionOutputStatus(output: 7, focusBits: 1, layoutLen: 2)]
  result.outputStatuses[0].layout[0] = byte('i')
  result.outputStatuses[0].layout[1] = byte('3')
  result.tabGroups = @[
    ProjectionTabGroup(
      output: 7,
      group: 31,
      width: 100,
      height: 100,
      selectedGeneration: 1,
      focused: true,
      members: @[member],
    )
  ]
  result.translationGroups = @[
    ProjectionTranslationGroup(output: 7, group: 32, x: -2, y: -3, members: @[member])
  ]
  result.launchContexts =
    @[LaunchOriginRecord(surfaceIndex: 0, surfaceGeneration: 1, epoch: 9, token: 77)]
  result.outputLaunchContexts =
    @[OutputLaunchContext(output: 7, generation: 1, epoch: 9, token: 88)]
  let coverage = Rect(width: 640, height: 480)
  let box = Rect(width: 100, height: 100)
  result.presentation = some(
    WmPresentation(
      generation: 5,
      keyboardOutput: 7,
      outputs: @[
        PresentationOutput(
          output: 7,
          generation: 1,
          coverage: coverage,
          mode: PresentationMode.replaceApplications,
        )
      ],
      instances: @[
        SurfaceInstance(
          id: 61,
          generation: 1,
          output: 7,
          sourceIndex: 0,
          sourceGeneration: 1,
          destination: box,
          clip: box,
          opacityMillis: 1000,
          zIndex: 1,
          action: 11,
        )
      ],
      regions: @[
        PresentationRegion(
          id: 62,
          generation: 1,
          output: 7,
          geometry: coverage,
          clip: coverage,
          role: PresentationRegionRole.backdrop,
        )
      ],
      bindings: @[PresentationBinding(action: 11, keycode: 16)],
    )
  )

proc baseFileProjection*(): PolicyProjection =
  result = fileProjection()
  result.indicators = @[]
  result.outputStatuses = @[]
  result.tabGroups = @[]
  result.presentation = none(WmPresentation)
