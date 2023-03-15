#!/bin/bash
# open-cravat 0.0.1
# Generated by dx-app-wizard.
#
# Basic execution pattern: Your app will run on a single machine from
# beginning to end.
#
# Your job's input variables (if any) will be loaded as environment
# variables before this script runs.  Any array inputs will be loaded
# as bash arrays.
#
# Any code outside of main() (or any entry point you may add) is
# ALWAYS executed, followed by running the entry point itself.
#
# See https://documentation.dnanexus.com/developer for tutorials on how
# to modify this file.

main() {
    
    set -x

    echo "Value of input_file: '$input_file'"
    echo "Value of package: '$package'"
    echo "Value of annotators: '${annotators[@]}'"
    echo "Value of genome: '$genome'"
    echo "Value of store_url: '$store_url'"

    if (( ${#annotators[@]} ));
    then
        addtlAnnotators=true
    else
        addtlAnnotators=false
    fi

    containerRef='karchinlab/opencravat:latest'
    docker pull $containerRef

    # The following line(s) use the dx command-line tool to download your file
    # inputs to the local file system using variable names for the filenames. To
    # recover the original filenames, you can use the output of "dx describe
    # "$variable" --name".
    input_fn=`dx describe "$input_file" --name`
    dx download "$input_file" -o "$input_fn"

    # Fill in your application code here.
    #
    # To report any recognized errors in the correct format in
    # $HOME/job_error.json and exit this script, you can use the
    # dx-jobutil-report-error utility as follows:
    #
    #   dx-jobutil-report-error "My error message"
    #
    # Note however that this entire bash script is executed with -e
    # when running in the cloud, so any line which returns a nonzero
    # exit code will prematurely exit the script; if no error was
    # reported in the job_error.json file, then the failure reason
    # will be AppInternalError with a generic error message.

    # The following line(s) use the dx command-line tool to upload your file
    # outputs after you have created them on the local file system.  It assumes
    # that you have used the output field name for the filename for each output,
    # but you can change that behavior to suit your needs.  Run "dx upload -h"
    # to see more options to set metadata.
    
    # Set store to S3 mirror
    mkdir conf
    docker run \
        -v $PWD/conf:/mnt/newconf \
        $containerRef cp /mnt/conf/cravat-system.yml /mnt/newconf
    docker run \
        -v $PWD/conf:/mnt/newconf \
        $containerRef cp /mnt/conf/cravat.yml /mnt/newconf
    sed -i conf/cravat-system.yml -e '/store_url/d'
    echo "store_url: $store_url" >> conf/cravat-system.yml

    # Download modules
    mkdir md
    docker run \
        -v $PWD/md:/mnt/modules \
	    -v $PWD/conf:/mnt/conf \
        $containerRef oc module install-base
    docker run \
        -v $PWD/md:/mnt/modules \
	    -v $PWD/conf:/mnt/conf \
        $containerRef oc module install -y vcfreporter
    docker run \
        -v $PWD/md:/mnt/modules \
	    -v $PWD/conf:/mnt/conf \
        $containerRef oc module install -y $package
    
    # Install additional annotators
    if [ $addtlAnnotators = true ]
    then
        docker run \
            -v $PWD/md:/mnt/modules \
            -v $PWD/conf:/mnt/conf \
            $containerRef oc module install -y ${annotators[@]}
    fi
    
    # Run job
    mkdir job
    mv $input_fn job
    runArgs=(oc run "$input_fn" "--package" "$package" "-l" "$genome")
    if [ $addtlAnnotators = true ]
    then
        runArgs+=("-a" ${annotators[@]})
    fi
    docker run \
        -v $PWD/md:/mnt/modules \
	    -v $PWD/conf:/mnt/conf \
        -v $PWD/job:/tmp/job \
        -w /tmp/job \
        $containerRef ${runArgs[@]}

    # Run vcf report
    docker run \
        -v $PWD/md:/mnt/modules \
	    -v $PWD/conf:/mnt/conf \
        -v $PWD/job:/tmp/job \
        -w /tmp/job \
        $containerRef oc report "$input_fn".sqlite -t vcf
    
    gzip "job/$input_fn.vcf"

    # The following line(s) use the utility dx-jobutil-add-output to format and
    # add output variables to your job's output as appropriate for the output
    # class.  Run "dx-jobutil-add-output -h" for more information on what it
    # does.

    ls job

    sqlite=$(dx upload "job/$input_fn.sqlite" --brief)
    log=$(dx upload "job/$input_fn.log" --brief)
    err=$(dx upload "job/$input_fn.err" --brief)
    vcf=$(dx upload "job/$input_fn.vcf.gz" --brief)

    dx-jobutil-add-output sqlite "$sqlite" --class=file
    dx-jobutil-add-output log "$log" --class=file
    dx-jobutil-add-output err "$err" --class=file
    dx-jobutil-add-output vcf "$vcf" --class=file
}
