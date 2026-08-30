import ReviewModePicker from "./_components/ReviewModePicker";

// Mode chooser — the target of the "Давтах" nav tab.
//
// It was a plain Server Component of three identical link cards. That looked
// tidy and answered the wrong question: it asked which mode you wanted without
// saying whether anything was due, and two of the three options serve only
// scheduled cards, so on a finished day you picked one and got an empty-state
// screen. The picker is a Client Component now because it reads due_summary()
// (per selected deck) and the deck list — see ReviewModePicker for the rest.
export default function ReviewPage() {
  return <ReviewModePicker />;
}
