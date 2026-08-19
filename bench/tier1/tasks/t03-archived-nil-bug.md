Bug: projects created without explicitly setting the archived flag never show up on the
projects index. If you do Project.create!(name: "New thing") and then hit the index, it
isn't there — but Project.count went up, and fetching it by id works fine. It only appears
once you explicitly set archived to false. Existing rows are fine. Find the root cause,
fix it properly (including any existing rows that are in this state), and add a test that
would have caught it.
