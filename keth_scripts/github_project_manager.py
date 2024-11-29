import os

import requests
from github import Github


def make_graphql_request(token: str, query: str, variables: dict) -> dict:
    """Make a GraphQL request to GitHub's API."""
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github.v4+json",
    }
    response = requests.post(
        "https://api.github.com/graphql",
        json={"query": query, "variables": variables},
        headers=headers,
    )
    response.raise_for_status()
    json_response = response.json()
    if "errors" in json_response:
        print("GraphQL Errors:", json_response["errors"])
        raise Exception(f"GraphQL request failed: {json_response['errors']}")
    if "data" not in json_response:
        print("Unexpected response:", json_response)
        raise Exception("No data in response")
    return json_response["data"]


def clear_project_items(token: str, project_id: str) -> None:
    """Remove all items from a GitHub project."""
    query = """
    query($project_id: ID!, $first: Int!) {
        node(id: $project_id) {
            ... on ProjectV2 {
                items(first: $first) {
                    nodes {
                        id
                    }
                }
            }
        }
    }
    """

    delete_mutation = """
    mutation($project_id: ID!, $item_id: ID!) {
        deleteProjectV2Item(input: {
            projectId: $project_id
            itemId: $item_id
        }) {
            deletedItemId
        }
    }
    """

    # First get all items
    variables = {"project_id": project_id, "first": 100}  # Adjust if needed
    result = make_graphql_request(token, query, variables)

    # Then delete each item
    for item in result["node"]["items"]["nodes"]:
        variables = {"project_id": project_id, "item_id": item["id"]}
        make_graphql_request(token, delete_mutation, variables)


def get_issue_node_id(token: str, owner: str, repo: str, issue_number: int) -> str:
    """Get the node ID of an issue using the REST API."""
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github.v3+json",
    }
    response = requests.get(
        f"https://api.github.com/repos/{owner}/{repo}/issues/{issue_number}",
        headers=headers,
    )
    response.raise_for_status()
    return response.json()["node_id"]


def add_issues_to_project(
    gh: Github, token: str, repo_full_name: str, project_id: str
) -> None:
    """Add all issues from a repository to a GitHub project."""
    # Get only issues (not PRs) using the search API
    query = f"repo:{repo_full_name} is:issue"
    issues = list(gh.search_issues(query))
    print(f"\nFound {len(issues)} issues")

    add_mutation = """
    mutation($project_id: ID!, $content_id: ID!) {
        addProjectV2ItemById(input: {
            projectId: $project_id
            contentId: $content_id
        }) {
            item {
                id
            }
        }
    }
    """

    owner, name = repo_full_name.split("/")
    issues_added = 0

    for issue in issues:
        try:
            # Get the node ID for this issue
            issue_id = get_issue_node_id(token, owner, name, issue.number)

            # Add the issue to the project
            variables = {"project_id": project_id, "content_id": issue_id}
            make_graphql_request(token, add_mutation, variables)
            print(f"Added issue #{issue.number}: {issue.title}")
            issues_added += 1
        except Exception as e:
            print(f"Failed to add issue #{issue.number}: {str(e)}")

    print("\nSummary:")
    print(f"Total issues found: {len(issues)}")
    print(f"Issues added: {issues_added}")


def main():
    # Get GitHub token from environment variable
    token = os.getenv("GITHUB_TOKEN")
    if not token:
        raise ValueError("Please set GITHUB_TOKEN environment variable")

    gh = Github(token)
    project_id = "PVT_kwDOBua6ec4AtO0l"  # The project ID we found

    repo_full_name = os.getenv("REPO_NAME")
    if not repo_full_name:
        raise ValueError("Please set REPO_NAME environment variable")

    print(f"Clearing all items from project {project_id}...")
    clear_project_items(token, project_id)
    print("Project cleared successfully")

    print(f"Adding issues from {repo_full_name} to project...")
    add_issues_to_project(gh, token, repo_full_name, project_id)


if __name__ == "__main__":
    main()
