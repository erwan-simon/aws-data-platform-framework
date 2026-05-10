import subprocess

def get_latest_data_platform_version():
	repo_url = "https://github.com/erwan-simon/aws-data-platform-framework"

	# Liste les tags distants
	tags_output = subprocess.check_output(
		["git", "ls-remote", "--tags", repo_url],
		text=True
	).strip()

	if not tags_output:
		raise ValueError("Aucun tag trouvé")

	# Chaque ligne = "<hash>\trefs/tags/<tag>"
	tags = [
		line.split("\t")[1].replace("refs/tags/", "")
		for line in tags_output.splitlines()]

	# On retire les tags annotés avec ^{}
	tags = [t for t in tags if not t.endswith("^{}")]

	# Trie par version (lexico si simple, semver si besoin)
	tags.sort()

	last_tag = tags[-1]
	print(f"Latest Data Platform version: {last_tag}")


if __name__ == "__main__":
	get_latest_data_platform_version()
