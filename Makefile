clean_master:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase0.yaml  -e "rollback=true"

clean_worker:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase2.yaml  -e "rollback=true"

install_master:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase0.yaml

copy_kubeconfig:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase1.yaml

install_worker:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase2.yaml

clean_reinstall:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase2.yaml  -e "rollback=true"
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase2.yaml

