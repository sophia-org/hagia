//! Real policy projection and Session admission. Surface observations and
//! settlement are supplied; no shell client, frontend or device is operated.
use super::*;
use sophia_engine::{IndicatorChromeAction, activate_indicator_at, layout_indicator_strip};

fn profile(layout: &str) -> String {
    format!(
        "schema 1\nshell {{ enabled #false; }}\nsession {{ terminal \"terminal\"; browser \"brave-origin\"; startup \"panel\"; }}\nshortcut {{ profile \"default\"; }}\npolicy {{ layout \"{layout}\"; outer-gap 0; inner-gap 0; }}\n"
    )
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_policy_tabs_commit_exact_member() {
    let mut run = Lifecycle::with_profile("policy-tabs", &profile("frame-tree"));
    populate_with_placements(&mut run, 1);
    let publication = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .reducer
        .indicator_publication();
    assert_eq!(publication.tab_groups.len(), 1);
    let group = &publication.tab_groups[0];
    assert_eq!(group.output, run.output.id);
    assert_eq!(group.members, SURFACES);
    assert_eq!(group.selected, focus(&run));
    let before = focus(&run).unwrap();
    let hidden = *group.members.iter().find(|&&s| s != before).unwrap();
    assert!(
        !run.layout.layers.contains_key(&hidden),
        "the selected target must really be hidden"
    );
    let checkpoint = run.checkpoint();
    for (surface, output) in [
        (
            SurfaceId::new(hidden.index(), hidden.generation() + 1),
            run.output.id,
        ),
        (hidden, OutputId::from_raw(run.output.id.raw() + 1)),
    ] {
        assert_eq!(
            run.wm.enqueue_tab_focus(surface, output).unwrap(),
            LiveWmRequestAdmission::Duplicate,
            "stale tab identity must not retarget the current member"
        );
        assert!(run.wm.public.as_ref().unwrap().queue.is_empty());
        assert_eq!(run.checkpoint(), checkpoint);
    }
    assert_eq!(
        run.wm.enqueue_tab_focus(hidden, run.output.id).unwrap(),
        LiveWmRequestAdmission::Admitted
    );
    let proposal = run.proposal();
    assert!(
        matches!(run.wm.public.as_ref().unwrap().in_flight_request.as_ref().unwrap().cause,
        PolicyRequestCause::Focus { target } if target == hidden)
    );
    assert_eq!(proposal.focus, Some(hidden));
    assert_eq!(
        focus(&run),
        Some(before),
        "tab selection changes focus only on commit"
    );
    assert_eq!(run.checkpoint(), checkpoint);
    run.commit(proposal);
    assert_checkpoint(&run);
    let publication = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .reducer
        .indicator_publication();
    assert_eq!(publication.tab_groups[0].members, SURFACES);
    assert_eq!(publication.tab_groups[0].selected, Some(hidden));
    assert_eq!(focus(&run), Some(hidden));
    assert!(!run.layout.layers.contains_key(&before));
    let style = run.wm.candidate_chrome_style();
    let clearance = style.clearance();
    assert!(clearance > 0, "real peer must negotiate visible chrome");
    let group = &publication.tab_groups[0];
    let work = run.wm.public.as_ref().unwrap().reducer.scene().outputs[0].work_area;
    let expected = Rect {
        x: group.geometry.x + clearance,
        y: group.geometry.y + group.geometry.height + clearance,
        width: group.geometry.width - 2 * clearance,
        height: work.y + work.height - group.geometry.y - group.geometry.height - 2 * clearance,
    };
    assert_eq!(
        run.layout.layers[&hidden].geometry, expected,
        "tab content must reserve its strip and negotiated chrome exactly once"
    );
    run.record("tab-selected");
    run.stop();
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_policy_indicator_activation_is_correlated() {
    let mut run = Lifecycle::with_profile("policy-indicators", &profile("scroller"));
    populate(&mut run);
    let publication = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .reducer
        .indicator_publication();
    let bounds = Rect {
        x: 0,
        y: 0,
        width: run.output.size.width,
        height: run.output.size.height,
    };
    let strip = layout_indicator_strip(&publication, run.output.id, bounds).unwrap();
    let snapshot = crate::shell_indicator_projection::indicator_snapshot(
        &publication,
        Some(run.output.id),
        91,
    );
    assert_eq!(snapshot.indicators.len(), 9);
    let indicator = snapshot.indicators.iter().find(|i| i.slot == 2).unwrap();
    let target = strip
        .hit_targets
        .iter()
        .find(|t| t.indicator == indicator.indicator)
        .unwrap();
    let point = Point {
        x: f64::from(target.geometry.x + target.geometry.width / 2),
        y: f64::from(target.geometry.y + target.geometry.height / 2),
    };
    let action = WmActionId::from_raw(indicator.action);
    assert_eq!(
        activate_indicator_at(&publication, &strip.hit_targets, point),
        IndicatorChromeAction::Activated {
            output: run.output.id,
            action
        }
    );
    assert_eq!(
        activate_indicator_at(
            &publication,
            &strip.hit_targets,
            Point {
                x: point.x,
                y: f64::from(strip.geometry.y + strip.geometry.height)
            }
        ),
        IndicatorChromeAction::Missed
    );
    let activation = ShellIndicatorActivation {
        connection_epoch: snapshot.connection_epoch,
        snapshot_generation: snapshot.generation,
        output: indicator.output,
        indicator: indicator.indicator,
        action: indicator.action,
        event_id: 1,
    };
    use crate::live_session::metadata_shell::indicators::classify_indicator_activation;
    assert_eq!(
        classify_indicator_activation(Some(&snapshot), &activation),
        ShellIndicatorActivationStatus::Accepted
    );
    assert_eq!(
        classify_indicator_activation(
            Some(&snapshot),
            &ShellIndicatorActivation {
                snapshot_generation: snapshot.generation + 1,
                ..activation
            }
        ),
        ShellIndicatorActivationStatus::Stale,
        "indicator activation must reject a stale publication"
    );
    assert_eq!(
        classify_indicator_activation(
            Some(&snapshot),
            &ShellIndicatorActivation {
                action: u64::MAX,
                ..activation
            }
        ),
        ShellIndicatorActivationStatus::Unknown,
        "indicator activation must reject a mismatched action"
    );
    let checkpoint = run.checkpoint();
    let before = focus(&run);
    let admitted = run
        .wm
        .enqueue_indicator_action(action, run.output.id)
        .unwrap();
    assert_eq!(admitted.admission, LiveWmRequestAdmission::Admitted);
    let proposal = run.proposal();
    assert!(
        matches!(run.wm.public.as_ref().unwrap().in_flight_request.as_ref().unwrap().cause,
        PolicyRequestCause::OutputAction { activation_serial, action: actual, output, .. }
        if Some(activation_serial) == admitted.activation_serial && actual == action && output == run.output.id)
    );
    assert_eq!(run.checkpoint(), checkpoint);
    assert_eq!(focus(&run), before);
    assert_eq!(
        proposal.focus, None,
        "the selected empty workspace must have no focused window"
    );
    run.commit(proposal);
    assert_eq!(focus(&run), None);
    let current = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .reducer
        .indicator_publication();
    assert_ne!(current.generation, publication.generation);
    assert_eq!(
        activate_indicator_at(&current, &strip.hit_targets, point),
        IndicatorChromeAction::Stale
    );
    assert_eq!(
        model(&run)["outputs"][0]["activeView"].as_u64(),
        Some(indicator.indicator)
    );
    run.record("indicator-committed");
    run.stop();
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_policy_translation_matches_checkpoint() {
    let document = profile("scroller").replace(
        "inner-gap 0;",
        "inner-gap 0; default-column-width { fixed 900; };",
    );
    let mut run = Lifecycle::with_profile("policy-translation", &document);
    populate(&mut run);
    let mut offsets = Vec::new();
    for name in ["focus-next", "focus-prev"] {
        let proposal = action(&mut run, name);
        assert!(
            proposal
                .layers
                .iter()
                .all(|layer| layer.translation.is_some()),
            "real scrolling projection must reach every translated layer"
        );
        run.commit(proposal);
        assert_checkpoint(&run);
        let checkpoint = model(&run);
        let view_id = checkpoint["outputs"][0]["activeView"].as_u64().unwrap();
        let view = checkpoint["views"]
            .as_array()
            .unwrap()
            .iter()
            .find(|v| v["id"].as_u64() == Some(view_id))
            .unwrap();
        let offset = view["viewportOffset"].as_i64().unwrap();
        offsets.push(offset);
        assert_eq!(run.layout.layers.len(), SURFACES.len());
        for layer in run.layout.layers.values() {
            let translation = layer
                .translation
                .expect("committed layer retains the peer translation");
            assert_eq!(translation.group, view_id);
            assert_eq!(
                translation.connection_epoch,
                run.wm.public.as_ref().unwrap().connection_epoch
            );
            assert_eq!(i64::from(translation.x), -offset);
            assert_eq!(translation.y, 0);
            let index = SURFACES
                .iter()
                .position(|surface| *surface == layer.surface)
                .unwrap();
            let work = run.wm.public.as_ref().unwrap().reducer.scene().outputs[0].work_area;
            assert_eq!(
                i64::from(layer.geometry.x),
                i64::from(work.x) + index as i64 * 900 - offset
                    + i64::from(run.wm.candidate_chrome_style().clearance()),
                "committed content position must follow the peer's scrolling camera"
            );
        }
    }
    assert!(
        offsets.iter().any(|offset| *offset != 0),
        "fixture must distinguish an omitted translation"
    );
    assert_ne!(
        offsets[0], offsets[1],
        "focus changes must move the scrolling camera"
    );
    run.record("translations-committed");
    run.stop();
}
