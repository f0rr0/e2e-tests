#!/bin/sh

set -eu

no_negatives () {
	echo "$(( $1 < 0 ? 0 : $1 ))"
}

echo "setting up ssh repo"

mkdir -p ~/.ssh
echo "$SSH_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
ssh-keyscan github.com >> ~/.ssh/known_hosts

git config --global user.email "prismabots@gmail.com"
git config --global user.name "Prismo"

git remote add github "git@github.com:$GITHUB_REPOSITORY.git"

# since GH actions are limited to 5 minute cron jobs, just run this continuously for 5 minutes
minutes=5 # cron job runs each x minutes
interval=10 # run each x seconds
i=0
count=$(((minutes * 60) / interval))
echo "running loop $count times"
while [ $i -le $count ]; do
	# increment to prevent forgetting incrementing, and also prevent overlapping with the next 5-minute job
	i=$(( i + 1 ))
	echo "run $i"

	start=$(date "+%s")

	dir=$(pwd)

	git pull github "${GITHUB_REF}" --ff-only
	packages=$(find . -not -path "*/node_modules/*" -type f -name "package.json")

	echo "checking info..."

	channel="alpha"
	v=$(yarn info prisma2@$channel --json | jq '.data["dist-tags"].alpha' | tr -d '"')

	echo "$packages" | tr ' ' '\n' | while read -r item; do
		echo "checking $item"
		cd "$(dirname "$item")/"

		vPrisma2="$(node -e "console.log(require('./package.json').devDependencies['prisma2'])")"

		if [ "$v" != "$vPrisma2" ]; then
			echo "$item: prisma2 expected $v, actual $vPrisma2"
			yarn add "prisma2@$v" --dev
		fi

		vPhoton="$(node -e "console.log(require('./package.json').dependencies['@prisma/photon'])")"

		if [ "$v" != "$vPhoton" ]; then
			echo "$item: @prisma/photon expected $v, actual $vPhoton"
			yarn add "@prisma/photon@$v"
		fi

		cd "$dir"
	done

	if [ -z "$(git status -s)" ]; then
		echo "no changes"
		end=$(date "+%s")
		diff=$(echo "$end - $start" | bc)
		remaining=$((interval - 1 - diff))
		echo "took $diff seconds, sleeping for $remaining seconds"
		sleep "$(no_negatives $remaining)"

		continue
	fi

	echo "changes, upgrading..."

	git commit -am "chore(packages): bump prisma2 to $v"

	# fail silently, as there's a chance that this change already has been pushed either manually
	# or by an overlapping upgrade action, as the yarn upgrade process can take multiple minutes
	git pull --rebase || true
	git push github HEAD:"${GITHUB_REF}" || true

	echo "pushed commit"

	end=$(date "+%s")
	diff=$(echo "$end - $start" | bc)
	remaining=$((interval - 1 - diff))
	echo "took $diff seconds, sleeping for $remaining seconds"
	sleep "$(no_negatives $remaining)"
done

echo "done"
