import ../types/model

proc adjustGapSizes*(model: var PolicyModel, step: int64) =
  if model.settings.gapModel == GapModel.uniform:
    model.settings.gaps =
      int32(clamp(int64(model.settings.gaps) + step, 0'i64, int64(maxGap)))
  else:
    model.settings.outerGap =
      int32(clamp(int64(model.settings.outerGap) + step, 0'i64, int64(maxGap)))
    model.settings.innerGap =
      int32(clamp(int64(model.settings.innerGap) + step, 0'i64, int64(maxGap)))
  model.settings.gapsEnabled = true

proc setGapsEnabled*(model: var PolicyModel, enabled: bool) =
  model.settings.gapsEnabled = enabled
