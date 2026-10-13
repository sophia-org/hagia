//! Actual Session publication admission and backend native installation.
//! Initialization and device completion are simulated; installation itself
//! must queue the frame. Sources, mapped facts and router times are supplied.
use super::*;
use sophia_backend_live::session_policy_presentation_fixture::SessionPolicyPresentationFixture;

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_native_publication_installation_queues_frame() {
    let mut target = None;
    let Held {
        mut run,
        mut content,
        first,
        ..
    } = held_with_install("native-publication-installation", |run, content| {
        let mut native = SessionPolicyPresentationFixture::new(&[run.output]);
        native.simulate_initialization(&mut content.runtime);
        assert!(content.runtime.policy_presentation().is_none());
        assert!(!native.queued(run.output.id));
        let heads = native.heads();
        run.wm
            .install_committed_policy_presentation_with(
                &mut content.runtime,
                true,
                false,
                &heads,
                |runtime, desired| native.install(runtime, &content.scene, desired),
            )
            .unwrap();
        assert!(
            native.queued(run.output.id),
            "Session installation must queue the native publication"
        );
        target = Some(native);
    });
    let mut target = target.unwrap();
    let output = first.outputs[0];
    assert_eq!(
        content.runtime.policy_presentation(),
        Some(&LivePolicyPresentation {
            owner_epoch: 1,
            presentation: first.clone(),
        })
    );
    assert!(receipts(&run).is_empty());
    assert!(
        run.wm
            .public
            .as_ref()
            .unwrap()
            .presentation_input
            .output_receipt(output.output)
            .is_none()
    );
    target.simulate_submit(output.output);
    for head in 0..2 {
        target.simulate_head_completion(&mut content.runtime, output.output, head);
        service(&mut run, content.runtime.input_projections());
        if head == 0 {
            assert!(
                receipts(&run).is_empty(),
                "installation cannot retire the other head"
            );
        }
    }
    let receipt = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .presentation_input
        .output_receipt(output.output)
        .unwrap();
    assert_eq!(receipt.outcome, PolicyPresentationOutcome::Presented);
    assert_eq!(
        (
            receipt.connection_epoch,
            receipt.publication_generation,
            receipt.output_generation
        ),
        (1, first.generation, output.generation)
    );
    assert_eq!(receipts(&run), vec![receipt]);
    let stamp = content.runtime.input_projections()[0]
        .policy_publication
        .as_ref()
        .unwrap();
    assert_eq!(
        (
            stamp.owner_epoch,
            stamp.generation,
            stamp.output,
            stamp.output_generation
        ),
        (1, first.generation, output.output, output.generation)
    );
    assert!(first.instances.iter().all(|instance| {
        stamp
            .instances
            .contains(&(instance.id, instance.generation))
    }));
    drain(&mut run);
    log(
        &run,
        "native_installation=production_shared_owner native_queue=automatic initialization=simulated completion=simulated_per_head receipts=backend_derived",
    );
    run.record("native-publication-presented");
    run.stop();
}
