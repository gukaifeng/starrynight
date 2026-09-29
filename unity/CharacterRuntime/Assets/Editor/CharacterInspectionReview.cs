// Compatibility entry point for older development scripts. Revision 4 uses
// saved-view editing; the old release-to-reset assertions are historical evidence
// in docs/verification/conversation-controls, not the current product contract.
public static class CharacterInspectionReview
{
    public static void Run() => CharacterViewEditorReview.Run();
    public static void ReviewAndExportSimulator() => CharacterViewEditorReview.ReviewAndExportSimulator();
}
