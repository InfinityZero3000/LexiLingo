import { configure } from "@testing-library/react";

// The whole suite renders many pages in parallel; on a busy machine or CI runner a page
// can take longer than the one-second default to show its first row.
configure({ asyncUtilTimeout: 5000 });
