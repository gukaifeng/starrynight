using UnityEngine;
public static class ConversationControlsReview
{
    public static void BuildReviewAndExportSimulator()
    {
        BuildIos.Setup();BuildIos.Validate();
        CharacterInspectionReview.Run();VrchatOriginalMotionReview.Run();CharacterPerformanceReview.Run();
        // Reviews use clones; reopen the saved production scene before export.
        BuildIos.ExportPreparedSimulator();
        Debug.Log("CONVERSATION_CONTROLS_REVIEW_PASS");
    }
}
