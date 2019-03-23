package My::Toolset;

use strict;
use warnings;
use utf8;
use autodie    qw(open close chdir mkdir binmode);
use feature    qw(say state);
use Cwd        qw(getcwd);
use Data::Dump qw(dump);
use List::Util qw(first);
use Carp       qw(croak);
use DateTime;
use constant PI     => 4 * atan2(1, 1);
use constant ARRAY  => ref [];
use constant HASH   => ref {};
use constant SCALAR => ref \$0;
use Exporter qw(import);
our @EXPORT = qw(
    show_front_matter
    validate_argv
    reduce_data
    show_elapsed_real_time
    pause_shell
);
our @EXPORT_OK = qw(
    construct_timestamps
    construct_range
    rm_duplicates
    rm_empty
    calc_vol
);
our %EXPORT_TAGS = (
    all  => [@EXPORT, @EXPORT_OK],
    coding => [qw(
        show_front_matter
        validate_argv
        reduce_data
        show_elapsed_real_time
        pause_shell
        construct_timestamps
        construct_range
    )],
    rm => [qw(
        rm_duplicates
        rm_empty
    )],
);


our $PACKNAME = __PACKAGE__;
our $VERSION  = '1.00';
our $LAST     = '2019-03-23';
our $FIRST    = '2018-08-19';


sub show_front_matter {
    # """Display the front matter."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $prog_info_href = shift;
    croak "The 1st arg of [$sub_name] must be a hash ref!"
        unless ref $prog_info_href eq HASH;
    
    # Subroutine optional arguments
    my(
        $is_prog,
        $is_auth,
        $is_usage,
        $is_timestamp,
        $is_no_trailing_blkline,
        $is_no_newline,
        $is_copy,
    );
    my $lead_symb    = '';
    foreach (@_) {
        $is_prog                = 1  if /prog/i;
        $is_auth                = 1  if /auth/i;
        $is_usage               = 1  if /usage/i;
        $is_timestamp           = 1  if /timestamp/i;
        $is_no_trailing_blkline = 1  if /no_trailing_blkline/i;
        $is_no_newline          = 1  if /no_newline/i;
        $is_copy                = 1  if /copy/i;
        # A single non-alphanumeric character
        $lead_symb              = $_ if /^[^a-zA-Z0-9]$/;
    }
    my $newline = $is_no_newline ? "" : "\n";
    
    #
    # Fill in the front matter array.
    #
    my @fm;
    my $k = 0;
    my $border_len = $lead_symb ? 69 : 70;
    my %borders = (
        '+' => $lead_symb.('+' x $border_len).$newline,
        '*' => $lead_symb.('*' x $border_len).$newline,
    );
    
    # Top rule
    if ($is_prog or $is_auth) {
        $fm[$k++] = $borders{'+'};
    }
    
    # Program info, except the usage
    if ($is_prog) {
        $fm[$k++] = sprintf(
            "%s%s - %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{titl},
            $prog_info_href->{expl},
            $newline,
        );
        $fm[$k++] = sprintf(
            "%sVersion %s (%s)%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{vers},
            $prog_info_href->{date_last},
            $newline,
        );
    }
    
    # Timestamp
    if ($is_timestamp) {
        my %datetimes = construct_timestamps('-');
        $fm[$k++] = sprintf(
            "%sCurrent time: %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $datetimes{ymdhms},
            $newline
        );
    }
    
    # Author info
    if ($is_auth) {
        $fm[$k++] = $lead_symb.$newline if $is_prog;
        $fm[$k++] = sprintf(
            "%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{auth}{$_},
            $newline
        ) for qw(name posi affi mail);
    }
    
    # Bottom rule
    if ($is_prog or $is_auth) {
        $fm[$k++] = $borders{'+'};
    }
    
    # Program usage: Leading symbols are not used.
    if ($is_usage) {
        $fm[$k++] = $newline if $is_prog or $is_auth;
        $fm[$k++] = $prog_info_href->{usage};
    }
    
    # Feed a blank line at the end of the front matter.
    if (not $is_no_trailing_blkline) {
        $fm[$k++] = $newline;
    }
    
    #
    # Print the front matter.
    #
    if ($is_copy) {
        return @fm;
    }
    else {
        print for @fm;
        return;
    }
}


sub validate_argv {
    # """Validate @ARGV against %cmd_opts."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $argv_aref     = shift;
    my $cmd_opts_href = shift;
    
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $argv_aref eq ARRAY;
    croak "The 2nd arg of [$sub_name] must be a hash ref!"
        unless ref $cmd_opts_href eq HASH;
    
    # For yn prompts
    my $the_prog = (caller(0))[1];
    my $yn;
    my $yn_msg = "    | Want to see the usage of $the_prog? [y/n]> ";
    
    #
    # Terminate the program if the number of required arguments passed
    # is not sufficient.
    #
    my $argv_req_num = shift; # (OPTIONAL) Number of required args
    if (defined $argv_req_num) {
        my $argv_req_num_passed = grep $_ !~ /-/, @$argv_aref;
        if ($argv_req_num_passed < $argv_req_num) {
            printf(
                "\n    | You have input %s nondash args,".
                " but we need %s nondash args.\n",
                $argv_req_num_passed,
                $argv_req_num,
            );
            print $yn_msg;
            while ($yn = <STDIN>) {
                system "perldoc $the_prog" if $yn =~ /\by\b/i;
                exit if $yn =~ /\b[yn]\b/i;
                print $yn_msg;
            }
        }
    }
    
    #
    # Count the number of correctly passed command-line options.
    #
    
    # Non-fnames
    my $num_corr_cmd_opts = 0;
    foreach my $arg (@$argv_aref) {
        foreach my $v (values %$cmd_opts_href) {
            if ($arg =~ /$v/i) {
                $num_corr_cmd_opts++;
                next;
            }
        }
    }
    
    # Fname-likes
    my $num_corr_fnames = 0;
    $num_corr_fnames = grep $_ !~ /^-/, @$argv_aref;
    $num_corr_cmd_opts += $num_corr_fnames;
    
    # Warn if "no" correct command-line options have been passed.
    if (not $num_corr_cmd_opts) {
        print "\n    | None of the command-line options was correct.\n";
        print $yn_msg;
        while ($yn = <STDIN>) {
            system "perldoc $the_prog" if $yn =~ /\by\b/i;
            exit if $yn =~ /\b[yn]\b/i;
            print $yn_msg;
        }
    }
    
    return;
}


sub reduce_data {
    # """Reduce data and generate reporting files."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $sets_href = shift;
    my $cols_href = shift;
    croak "The 1st arg of [$sub_name] must be a hash ref!"
        unless ref $sets_href eq HASH;
    croak "The 2nd arg of [$sub_name] must be a hash ref!"
        unless ref $cols_href eq HASH;
    
    #
    # Available formats
    # [1] dat
    #   - Plottable text file
    #   - Created by this routine's architecture
    # [2] tex
    #   - Wrapped in the LaTeX tabular environment
    #   - Created by this routine's architecture
    # [3] csv
    #   - Comma-separated values (sep char can however be changed)
    #   - Created by the Text::CSV module
    # [4] xlsx
    #   - MS Excel >2007
    #   - Created by the Excel::Writer::XLSX module "in binary"
    # [5] json
    #   - Arguably the most popular data interchange language
    #   - Created by the JSON module
    # [6] yaml
    #   - An increasingly popular data interchange language
    #   - Created by the YAML module
    #
    # Accordingly, the lines of code for
    # > [1] and [2] are almost the same.
    # > [3] and [4] are essentially their modules' interfaces.
    # > [5] and [6] are a simple chunk of their modules' data dumping commands.
    #
    
    #
    # Default attributes
    #
    my %flags = ( # Available data formats
        dat  => qr/^dat$/i,
        tex  => qr/^tex$/i,
        csv  => qr/^csv$/i,
        xlsx => qr/^xlsx$/i,
        json => qr/^json$/i,
        yaml => qr/^yaml$/i,
    );
    my %sets = (
        rpt_formats => ['dat', 'tex'],
        rpt_path    => "./",
        rpt_bname   => "rpt",
        begin_msg   => "generating data reduction reports...",
    );
    my %cols;
    my %rows;
    my %strs = ( # Not to be modified via the user arguments
        symbs    => {dat => "#",    tex => "%"   },
        eofs     => {dat => "#eof", tex => "%eof"},
        nan      => {
            dat  => "NaN",
            tex  => "{}",
            csv  => "",
            xlsx => "",
            json => "", # Not related to its 'null'
            yaml => "", # Not related to its '~'
        },
        newlines => {
            dat => "\n",
            tex => " \\\\\n",
            csv => "\n",
        },
        dataset_seps => {
            dat => "\n\n", # wrto gnuplot dataset structure
        },
        indents  => {dat => "", tex => "  "},
        rules    => {
            dat  => {}, # To be constructed
            tex  => {   # Commands of the booktabs package
                top => "\\toprule",
                mid => "\\midrule",
                bot => "\\bottomrule",
            },
            xlsx => {   # Border indices (not borders)
                # Refer to the following URL for the border indices:
                # https://metacpan.org/pod/Excel::Writer::XLSX#set_border()
                none    => 0,
                top     => 2,
                mid     => 2,
                bot     => 2,
                mid_bot => 2, # For single-rowed data
            },
        },
    );
    # Override the attributes of %sets and %cols for given keys.
    # (CAUTION: Not the whole hashes!)
    $sets{$_} = $sets_href->{$_} for keys %$sets_href;
    $cols{$_} = $cols_href->{$_} for keys %$cols_href;
    
    #
    # Data format validation
    #
    @{$sets{rpt_formats}} = (keys %flags)
        if first { /all/i } @{$sets{rpt_formats}}; # 'all' format
    foreach my $rpt_format (@{$sets{rpt_formats}}) {
        next if (first { $rpt_format =~ $_ } values %flags);
        croak "[$sub_name]: [$rpt_format]".
              " is not a valid element of rpt_formats.\n".
              "Available formats are: ".
              join(", ", sort keys %flags)."\n";
    }
    
    #
    # Column size validation
    #
    croak "[$sub_name]: Column size must be provided via the size key."
        unless defined $cols{size};
    croak "[$sub_name]: Column size must be a positive integer."
        if $cols{size} <= 0 or $cols{size} =~ /[.]/;
    foreach (qw(heads subheads data_arr_ref)) {
        unless (@{$cols{$_}} % $cols{size} == 0) {
            croak
                "[$sub_name]\nColumn size [$_] is found to be".
                " [".@{$cols{$_}}."].\n".
                "It must be [$cols{size}] or its integer multiple!";
        }
    }
    
    #
    # Create some default key-val pairs.
    #
    # > Needless to say, a hash ref argument, if given, replaces
    #   an original hash ref. If some key-val pairs were assigned
    #   in the "Default attributes" section at the beginning of
    #   this routine but were not specified by the user arguments,
    #   those pairs would be lost:
    #   Original: space_bef => {dat => " ", tex => " "}
    #   User-arg: space_bef => {dat => " "}
    #   Defined:  space_bef => {dat => " "}
    #   The tex => " " pair would not be available hereafter.
    # > To avoid such loss, default key-val pairs are defined
    #   altogether below.
    # > This also allows the TeX separators, which must be
    #   the ampersand (&), immutable. That is, even if the following
    #   arguments are passed, the TeX separators will remain unchanged:
    #   User-arg: heads_sep => {dat => "|", csv => ";", tex => "|"}
    #             data_sep  => {dat => " ", csv => ";", tex => " "}
    #   Defined:  heads_sep => {dat => "|", csv => ";", tex => "&"}
    #             data_sep  => {dat => " ", csv => ";", tex => "&"}
    # > Finally, the headings separators for DAT and TeX are
    #   enclosed with the designated space characters.
    #   (i.e. space_bef and space_aft)
    # > CSV separators can be set via the user arguments,
    #   as its module defines such a method,
    #   but are not surrounded by any space characters.
    # > XLSX, as written in binaries, has nothing to do here.
    #
    
    # dat
    $cols{space_bef}{dat} = " " unless exists $cols{space_bef}{dat};
    $cols{heads_sep}{dat} = "|" unless exists $cols{heads_sep}{dat};
    $cols{space_aft}{dat} = " " unless exists $cols{space_aft}{dat};
    $cols{data_sep}{dat}  = " " unless exists $cols{data_sep}{dat};
    # TeX
    $cols{space_bef}{tex} = " " unless exists $cols{space_bef}{tex};
    $cols{heads_sep}{tex} = "&"; # Immutable
    $cols{space_aft}{tex} = " " unless exists $cols{space_aft}{tex};
    $cols{data_sep}{tex}  = "&"; # Immutable
    # DAT, TeX
    foreach (qw(dat tex)) {
        next if $cols{heads_sep}{$_} =~ /\t/; # Don't add spaces around a tab.
        $cols{heads_sep}{$_} =
            $cols{space_bef}{$_}.$cols{heads_sep}{$_}.$cols{space_aft}{$_};
    }
    # CSV
    $cols{heads_sep}{csv} = "," unless exists $cols{heads_sep}{csv};
    $cols{data_sep}{csv}  = "," unless exists $cols{data_sep}{csv};
    #+++++debugging+++++#
#    dump(\%cols);
#    pause_shell();
    #+++++++++++++++++++#
    
    #
    # Convert the data array into a "rowwise" columnar structure.
    #
    my $i = 0;
    for (my $j=0; $j<=$#{$cols{data_arr_ref}}; $j++) {
        push @{$cols{data_rowwise}[$i]}, $cols{data_arr_ref}[$j];
        #+++++debugging+++++#
#        say "At [\$i: $i] and [\$j: $j]: the modulus is: ",
#            ($j + 1) % $cols{size};
        #+++++++++++++++++++#
        $i++ if ($j + 1) % $cols{size} == 0;
    }
    
    #
    # Define row and column indices to be used for iteration controls.
    #
    $rows{idx_last}     = $#{$cols{data_rowwise}};
    $cols{idx_multiple} = $cols{size} - 1;
    
    # Obtain columnar data sums.
    if (defined $cols{sum_idx_multiples}) {
        for (my $i=0; $i<=$rows{idx_last}; $i++) {
            for (my $j=0; $j<=$cols{idx_multiple}; $j++) {
                    if (first { $j == $_ } @{$cols{sum_idx_multiples}}) {
                        $cols{data_sums}[$j] +=
                            $cols{data_rowwise}[$i][$j] // 0;
                }
            }
        }
    }
    #+++++debugging+++++#
#    dump(\%cols);
#    pause_shell();
    #+++++++++++++++++++#
    
    #
    # Notify the beginning of the routine.
    #
    say "\n#".('=' x 69);
    say "#"." [$sub_name] $sets{begin_msg}";
    say "#".('=' x 69);
    
    #
    # Multiplex outputting
    # IO::Tee intentionally not used for avoiding its additional installation
    #
    
    # Define filehandle refs and corresponding filenames.
    my($dat_fh, $tex_fh, $csv_fh, $xlsx_fh);
    my %rpt_formats = (
        dat  => {fh => $dat_fh,  fname => $sets{rpt_bname}.".dat" },
        tex  => {fh => $tex_fh,  fname => $sets{rpt_bname}.".tex" },
        csv  => {fh => $csv_fh,  fname => $sets{rpt_bname}.".csv" },
        xlsx => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".xlsx"},
        json => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".json"},
        yaml => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".yaml"},
    );
    
    # Multiple invocations of the writing routine
    my $cwd = getcwd();
    mkdir $sets{rpt_path} if not -e $sets{rpt_path};
    chdir $sets{rpt_path};
    foreach (@{$sets{rpt_formats}}) {
        open $rpt_formats{$_}{fh}, '>:encoding(UTF-8)', $rpt_formats{$_}{fname};
        reduce_data_writing_part(
            $rpt_formats{$_}{fh},
            $_, # Flag
            \%flags,
            \%sets,
            \%strs,
            \%cols,
            \%rows,
        );
        say "[$sets{rpt_path}/$rpt_formats{$_}{fname}] generated.";
    }
    chdir $cwd;
    
    #
    # The writing routine (nested)
    #
    sub reduce_data_writing_part {
        my $_fh    = $_[0];
        my $_flag  = $_[1];
        my %_flags = %{$_[2]};
        my %_sets  = %{$_[3]};
        my %_strs  = %{$_[4]};
        my %_cols  = %{$_[5]};
        my %_rows  = %{$_[6]};
        
        #
        # [CSV][XLSX] Load modules and instantiate classes.
        #
        
        # [CSV]
        my $csv;
        if ($_flag =~ $_flags{csv}) {
            require Text::CSV; # vendor lib || cpanm
            $csv = Text::CSV->new( { binary => 1 } )
                or die "Cannot instantiate Text::CSV! ".Text::CSV->error_diag();
            
            $csv->eol($_strs{newlines}{$_flag});
        }
        
        # [XLSX]
        my($workbook, $worksheet, %xlsx_formats);
        my($xlsx_row, $xlsx_col, $xlsx_col_init, $xlsx_col_scale_factor);
        $xlsx_row                  = 1;   # Starting row number
        $xlsx_col = $xlsx_col_init = 1;   # Starting col number
        $xlsx_col_scale_factor     = 1.2; # Empirically determined
        if ($_flag =~ $_flags{xlsx}) {
            require Excel::Writer::XLSX; # vendor lib || cpanm
            binmode($_fh); # fh can now be R/W in binary as well as in text
            $workbook = Excel::Writer::XLSX->new($_fh);
            
            # Define the worksheet name using the bare filename of the report.
            # If the bare filename contains a character that is invalid
            # as an Excel worksheet name or lengthier than 32 characters,
            # the default worksheet name is used (i.e. Sheet1).
            eval {
                $worksheet = $workbook->add_worksheet(
                    (split /\/|\\/, $_sets{rpt_bname})[-1]
                )
            };
            $worksheet = $workbook->add_worksheet() if $@;
            
            # As of Excel::Writer::XLSX v0.98, a format property
            # can be added in the middle, but cannot be overridden.
            # The author of this routine therefore uses cellwise formats
            # to specify "ruled" and "aligned" cells.
            foreach my $rule (keys %{$_strs{rules}{$_flag}}) {
                foreach my $align (qw(none left right)) {
                    $xlsx_formats{$rule}{$align}= $workbook->add_format(
                        top    => $rule =~ /top|mid/i ?
                            $_strs{rules}{$_flag}{$rule} : 0,
                        bottom => $rule =~ /bot/i ?
                            $_strs{rules}{$_flag}{$rule} : 0,
                        align  => $align,
                    );
                }
            }
            #+++++debugging+++++#
#            dump(\%xlsx_formats);
#            pause_shell();
            #+++++++++++++++++++#
            
            # Panes freezing
            # Added on 2018-11-23
            if ($_cols{freeze_panes}) {
                $worksheet->freeze_panes(
                    ref $_cols{freeze_panes} eq HASH ?
                        ($_cols{freeze_panes}{row}, $_cols{freeze_panes}{col}) :
                        $_cols{freeze_panes}
                );
            }
        }
        
        #
        # Data construction
        #
        
        # [DAT] Prepend comment symbols to the first headings.
        if ($_flag =~ $_flags{dat}) {
            $_cols{heads}[0]    = $_strs{symbs}{$_flag}." ".$_cols{heads}[0];
            $_cols{subheads}[0] = $_strs{symbs}{$_flag}." ".$_cols{subheads}[0];
        }
        if ($_flag !~ $_flags{dat}) { # Make it unaffected by the prev dat call
            $_cols{heads}[0]    =~ s/^[^\w] //;
            $_cols{subheads}[0] =~ s/^[^\w] //;
        }
        
        #
        # Define widths for columnar alignment.
        # (1) Take the lengthier one between headings and subheadings.
        # (2) Take the lengthier one between (1) and the data.
        # (3) Take the lengthier one between (2) and the data sum.
        #
        
        # (1)
        for (my $j=0; $j<=$#{$_cols{heads}}; $j++) {
            $_cols{widths}[$j] =
                length($_cols{heads}[$j]) > length($_cols{subheads}[$j]) ?
                length($_cols{heads}[$j]) : length($_cols{subheads}[$j]);
        }
        # (2)
        for (my $i=0; $i<=$_rows{idx_last}; $i++) {
            for (my $j=0; $j<=$#{$_cols{widths}}; $j++) {
                $_cols{widths}[$j] =
                    length($_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag})
                    > $_cols{widths}[$j] ?
                    length($_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag})
                    : $_cols{widths}[$j];
            }
        }
        # (3)
        if (defined $_cols{sum_idx_multiples}) {
            foreach my $j (@{$_cols{sum_idx_multiples}}) {
                $_cols{widths}[$j] =
                    length($_cols{data_sums}[$j]) > $_cols{widths}[$j] ?
                    length($_cols{data_sums}[$j]) : $_cols{widths}[$j];
            }
        }
        
        #
        # [DAT] Border construction
        #
        if ($_flag =~ $_flags{dat}) {
            $_cols{border_widths}[0] = 0;
            $_cols{border_widths}[1] = 0;
            for (my $j=0; $j<=$#{$_cols{widths}}; $j++) {
                # Border width 1: Rules
                $_cols{border_widths}[0] += (
                    $_cols{widths}[$j] + length($_cols{heads_sep}{$_flag})
                );
                # Border width 2: Data sums label
                if (defined $_cols{sum_idx_multiples}) {
                    if ($j < $_cols{sum_idx_multiples}[0]) {
                        $_cols{border_widths}[1] += (
                                     $_cols{widths}[$j]
                            + length($_cols{heads_sep}{$_flag})
                        );
                    }
                }
            }
            $_cols{border_widths}[0] -=
                (
                      length($_strs{symbs}{$_flag})
                    + length($_cols{space_aft}{$_flag})
                );
            $_cols{border_widths}[1] -=
                (
                      length($_strs{symbs}{$_flag})
                    + length($_cols{space_aft}{$_flag})
                );
            $_strs{rules}{$_flag}{top} =
            $_strs{rules}{$_flag}{mid} =
            $_strs{rules}{$_flag}{bot} =
                $_strs{symbs}{$_flag}.('-' x $_cols{border_widths}[0]);
        }
        
        #
        # Begin writing.
        # [JSON][YAML]: Via their dumping commands.
        # [DAT][TeX]:   Via the output filehandle.
        # [CSV][XLSX]:  Via their output methods.
        #
        
        # [JSON][YAML][DAT][TeX] Change the output filehandle from STDOUT.
        select($_fh);
        
        #
        # [JSON][YAML] Load modules and dump the data.
        #
        
        # [JSON]
        if ($_flag =~ $_flags{json}) {
            use JSON; # vendor lib || cpanm
            print to_json(\%_cols, { pretty => 1 });
        }
        
        # [YAML]
        if ($_flag =~ $_flags{yaml}) {
            use YAML; # vendor lib || cpanm
            print Dump(\%_cols);
        }
        
        # [DAT][TeX] OPTIONAL blocks
        if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
            # Prepend the program information, if given.
            if ($_sets{prog_info}) {
                show_front_matter(
                    $_sets{prog_info},
                    'prog',
                    'auth',
                    'timestamp',
                    ($_strs{symbs}{$_flag} // $_strs{symbs}{dat}),
                );
            }
            
            # Prepend comments, if given.
            if ($_sets{cmt_arr}) {
                if (@{$_sets{cmt_arr}}) {
                    say $_strs{symbs}{$_flag}.$_ for @{$_sets{cmt_arr}};
                    print "\n";
                }
            }
        }
        
        # [TeX] Wrapping up - begin
        if ($_flag =~ $_flags{tex}) {
            # Document class
            say "\\documentclass{article}";
            
            # Package loading with kind notice
            say "%";
            say "% (1) The \...rule commands are defined by".
                " the booktabs package.";
            say "% (2) If an underscore character is included as text,";
            say "%     you may want to use the underscore package.";
            say "%";
            say "\\usepackage{booktabs,underscore}";
            
            # document env - begin
            print "\n";
            say "\\begin{document}";
            print "\n";
            
            # tabular env - begin
            print "\\begin{tabular}{";
            for (my $j=0; $j<=$#{$_cols{heads}}; $j++) {
                print(
                    (first { $j == $_ } @{$_cols{ragged_left_idx_multiples}}) ?
                        "r" : "l"
                );
            }
            print "}\n";
        }
        
        # [DAT][TeX] Top rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{top}, "\n"
            if $_flag =~ /$_flags{dat}|$_flags{tex}/;
        
        #
        # Headings and subheadings
        #
        
        # [DAT][TeX]
        for (my $j=0; $j<=$#{$_cols{heads}}; $j++) {
            if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
                print $_strs{indents}{$_flag} if $j == 0;
                $_cols{conv} = '%-'.$_cols{widths}[$j].'s';
                if ($_cols{heads_sep}{$_flag} !~ /\t/) {
                    printf(
                        "$_cols{conv}%s",
                        $_cols{heads}[$j],
                        $j == $#{$_cols{heads}} ? '' : $_cols{heads_sep}{$_flag}
                    );
                }
                elsif ($_cols{heads_sep}{$_flag} =~ /\t/) {
                    printf(
                        "%s%s",
                        $_cols{heads}[$j],
                        $j == $#{$_cols{heads}} ? '' : $_cols{heads_sep}{$_flag}
                    );
                }
                print $_strs{newlines}{$_flag} if $j == $#{$_cols{heads}};
            }
        }
        for (my $j=0; $j<=$#{$_cols{subheads}}; $j++) {
            if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
                print $_strs{indents}{$_flag} if $j == 0;
                $_cols{conv} = '%-'.$_cols{widths}[$j].'s';
                if ($_cols{heads_sep}{$_flag} !~ /\t/) {
                    printf(
                        "$_cols{conv}%s",
                        $_cols{subheads}[$j],
                        $j == $#{$_cols{subheads}} ?
                            '' : $_cols{heads_sep}{$_flag}
                    );
                }
                elsif ($_cols{heads_sep}{$_flag} =~ /\t/) {
                    printf(
                        "%s%s",
                        $_cols{subheads}[$j],
                        $j == $#{$_cols{subheads}} ?
                            '' : $_cols{heads_sep}{$_flag}
                    );
                }
                print $_strs{newlines}{$_flag} if $j == $#{$_cols{subheads}};
            }
        }
        
        # [CSV][XLSX]
        if ($_flag =~ $_flags{csv}) {
            $csv->sep_char($_cols{heads_sep}{$_flag});
            $csv->print($_fh, $_cols{heads});
            $csv->print($_fh, $_cols{subheads});
        }
        if ($_flag =~ $_flags{xlsx}) {
            $worksheet->write_row(
                $xlsx_row++,
                $xlsx_col,
                $_cols{heads},
                $xlsx_formats{top}{none} # top rule formatted
            );
            $worksheet->write_row(
                $xlsx_row++,
                $xlsx_col,
                $_cols{subheads},
                $xlsx_formats{none}{none}
            );
        }
        
        # [DAT][TeX] Middle rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{mid}, "\n"
            if $_flag =~ /$_flags{dat}|$_flags{tex}/;
        
        #
        # Data
        #
        # > [XLSX] is now handled together with [DAT][TeX]
        #   to allow columnwise alignment. That is, the write() method
        #   is used instead of the write_row() one.
        # > Although MS Excel by default aligns numbers ragged left,
        #   the author wanted to provide this routine with more flexibility.
        # > According to the Excel::Writer::XLSX manual,
        #   AutoFit can only be performed from within Excel.
        #   By the use of write(), however, pseudo-AutoFit is also realized:
        #   The author has created this routine initially for gnuplot-plottable
        #   text file and TeX tabular data, and for them he added an automatic
        #   conversion creation functionality. Utilizing the conversion width,
        #   approximate AutoFit can be performed.
        #   To see how it works, look up:
        #     - 'Define widths for columnar alignment.' and the resulting
        #       values of $_cols{widths}
        #     - $xlsx_col_scale_factor
        #
        for (my $i=0; $i<=$_rows{idx_last}; $i++) {
            # [CSV]
            if ($_flag =~ $_flags{csv}) {
                $csv->sep_char($_cols{data_sep}{$_flag});
                $csv->print(
                    $_fh,
                    $_cols{data_rowwise}[$i] // $_strs{nan}{$_flag}
                );
            }
            # [DAT] Dataset separator
            # > Optional
            # > If designated, gnuplot dataset separator, namely a pair of
            #   blank lines, is inserted before beginning the next dataset.
            if (
                $_flag =~ $_flags{dat} and
                $_sets{num_rows_per_dataset} and # Make this loop optional.
                $i != 0 and                      # Skip the first row.
                $i % $_sets{num_rows_per_dataset} == 0
            ) {
                print $_strs{dataset_seps}{$_flag};
            }
            # [DAT][TeX][XLSX]
            $xlsx_col = $xlsx_col_init;
            for (my $j=0; $j<=$_cols{idx_multiple}; $j++) {
                # [DAT][TeX]
                if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
                    # Conversion (i): "Ragged right"
                    # > Default
                    # > length($_cols{space_bef}{$_flag})
                    #   is "included" in the conversion.
                    $_cols{conv} =
                        '%-'.
                        (
                                     $_cols{widths}[$j] 
                            + length($_cols{space_bef}{$_flag})
                        ).
                        's';
                    
                    # Conversion (ii): "Ragged left"
                    # > length($_cols{space_bef}{$_flag})
                    #   is "appended" to the conversion.
                    if (first { $j == $_ } @{$_cols{ragged_left_idx_multiples}})
                    {
                        $_cols{conv} =
                            '%'.
                            $_cols{widths}[$j].
                            's'.
                            (
                                $j == $_cols{idx_multiple} ?
                                    '' : ' ' x length($_cols{space_bef}{$_flag})
                            );
                    }
                    
                    # Columns
                    print $_strs{indents}{$_flag} if $j == 0;
                    if ($_cols{data_sep}{$_flag} !~ /\t/) {
                        printf(
                            "%s$_cols{conv}%s",
                            ($j == 0 ? '' : $_cols{space_aft}{$_flag}),
                            $_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag},
                            (
                                $j == $_cols{idx_multiple} ?
                                    '' : $_cols{data_sep}{$_flag}
                            )
                        );
                    }
                    elsif ($_cols{data_sep}{$_flag} =~ /\t/) {
                        printf(
                            "%s%s",
                            $_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag},
                            (
                                $j == $_cols{idx_multiple} ?
                                    '' : $_cols{data_sep}{$_flag}
                            )
                        );
                    }
                    print $_strs{newlines}{$_flag}
                        if $j == $_cols{idx_multiple};
                }
                # [XLSX]
                if ($_flag =~ $_flags{xlsx}) {
                    # Pseudo-AutoFit
                    $worksheet->set_column(
                        $xlsx_col,
                        $xlsx_col,
                        $_cols{widths}[$j] * $xlsx_col_scale_factor
                    );
                    
                    my $_align = (
                        first { $j == $_ } @{$_cols{ragged_left_idx_multiples}}
                    ) ? 'right' : 'left';
                    $worksheet->write(
                        $xlsx_row,
                        $xlsx_col,
                        $_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag},
                        ($i == 0 and $i == $_rows{idx_last}) ?
                            $xlsx_formats{mid_bot}{$_align} : # For single-rowed
                        $i == 0 ?
                            $xlsx_formats{mid}{$_align} : # mid rule formatted
                        $i == $_rows{idx_last} ?
                            $xlsx_formats{bot}{$_align} : # bot rule formatted
                            $xlsx_formats{none}{$_align}  # Default: no rule
                    );
                    $xlsx_col++;
                    $xlsx_row++ if $j == $_cols{idx_multiple};
                }
            }
        }
        
        # [DAT][TeX] Bottom rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{bot}, "\n"
            if $_flag =~ /$_flags{dat}|$_flags{tex}/;
        
        #
        # Append the data sums.
        #
        if (defined $_cols{sum_idx_multiples}) {
            #
            # [DAT] Columns "up to" the beginning of the data sums
            #
            if ($_flag =~ $_flags{dat}) {
                my $sum_lab         = "Sum: ";
                my $sum_lab_aligned = sprintf(
                    "%s%s%s%s",
                    $_strs{indents}{$_flag},
                    $_strs{symbs}{$_flag},
                    ' ' x ($_cols{border_widths}[1] - length($sum_lab)),
                    $sum_lab
                );
                print $sum_lab_aligned;
            }
            
            #
            # Columns "for" the data sums
            #
            
            # [DAT][TeX][XLSX]
            my $the_beginning = $_flag !~ $_flags{dat} ?
                0 : $_cols{sum_idx_multiples}[0];
            $xlsx_col = $xlsx_col_init;
            for (my $j=$the_beginning; $j<=$_cols{sum_idx_multiples}[-1]; $j++)
            {
                # [DAT][TeX]
                if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
                    # Conversion (i): "Ragged right"
                    # > Default
                    # > length($_cols{space_bef}{$_flag})
                    #   is "included" in the conversion.
                    $_cols{conv} =
                        '%-'.
                        (
                                     $_cols{widths}[$j] 
                            + length($_cols{space_bef}{$_flag})
                        ).
                        's';
                    
                    # Conversion (ii): "Ragged left"
                    # > length($_cols{space_bef}{$_flag})
                    #   is "appended" to the conversion.
                    if (first { $j == $_ } @{$_cols{ragged_left_idx_multiples}})
                    {
                        $_cols{conv} =
                            '%'.
                            $_cols{widths}[$j].
                            's'.
                            (
                                $j == $_cols{idx_multiple} ?
                                    '' : ' ' x length($_cols{space_bef}{$_flag})
                            );
                    }
                    
                    # Columns
                    print $_strs{indents}{$_flag} if $j == 0;
                    if ($_cols{data_sep}{$_flag} !~ /\t/) {
                        printf(
                            "%s$_cols{conv}%s",
                            ($j == 0 ? '' : $_cols{space_bef}{$_flag}),
                            $_cols{data_sums}[$j] // $_strs{nan}{$_flag},
                            (
                                $j == $_cols{sum_idx_multiples}[-1] ?
                                    '' : $_cols{data_sep}{$_flag}
                            )
                        );
                    }
                    elsif ($_cols{data_sep}{$_flag} =~ /\t/) {
                        printf(
                            "%s%s",
                            $_cols{data_sums}[$j] // $_strs{nan}{$_flag},
                            (
                                $j == $_cols{sum_idx_multiples}[-1] ?
                                    '' : $_cols{data_sep}{$_flag}
                            )
                        );
                    }
                    print $_strs{newlines}{$_flag}
                        if $j == $_cols{sum_idx_multiples}[-1];
                }
                # [XLSX]
                if ($_flag =~ $_flags{xlsx}) {
                    my $_align = (
                        first { $j == $_ } @{$_cols{ragged_left_idx_multiples}}
                    ) ? 'right' : 'left';
                    
                    $worksheet->write(
                        $xlsx_row,
                        $xlsx_col,
                        $_cols{data_sums}[$j] // $_strs{nan}{$_flag},
                        $xlsx_formats{none}{$_align}
                    );
                    
                    $xlsx_col++;
                    $xlsx_row++ if $j == $_cols{sum_idx_multiples}[-1];
                }
            }
            
            # [CSV]
            if ($_flag =~ $_flags{csv}) {
                $csv->print(
                    $_fh,
                    $_cols{data_sums} // $_strs{nan}{$_flag}
                );
            }
        }
        
        # [TeX] Wrapping up - end
        if ($_flag =~ $_flags{tex}) {
            # tabular env - end
            say '\\end{tabular}';
            
            # document env - end
            print "\n";
            say "\\end{document}";
        }
        
        # [DAT][TeX] EOF
        print $_strs{eofs}{$_flag} if $_flag =~ /$_flags{dat}|$_flags{tex}/;
        
        # [JSON][YAML][DAT][TeX] Restore the output filehandle to STDOUT.
        select(STDOUT);
        
        # Close the filehandle.
        # the XLSX filehandle must be closed via its close method!
        close $_fh         if $_flag !~ $_flags{xlsx};
        $workbook->close() if $_flag =~ $_flags{xlsx};
    }
    
    return;
}


sub show_elapsed_real_time {
    # """Show the elapsed real time."""
    
    my @opts = @_ if @_;
    
    # Parse optional arguments.
    my $is_return_copy = 0;
    my @del; # Garbage can
    foreach (@opts) {
        if (/copy/i) {
            $is_return_copy = 1;
            # Discard the 'copy' string to exclude it from
            # the optional strings that are to be printed.
            push @del, $_;
        }
    }
    my %dels = map { $_ => 1 } @del;
    @opts = grep !$dels{$_}, @opts;
    
    # Optional strings printing
    print for @opts;
    
    # Elapsed real time printing
    my $elapsed_real_time = sprintf("Elapsed real time: [%s s]", time - $^T);
    
    # Return values
    if ($is_return_copy) {
        return $elapsed_real_time;
    }
    else {
        say $elapsed_real_time;
        return;
    }
}


sub pause_shell {
    # """Pause the shell."""
    
    my $notif = $_[0] ? $_[0] : "Press enter to exit...";
    
    print $notif;
    while (<STDIN>) { last; }
    
    return;
}


sub construct_timestamps {
    # """Construct timestamps."""
    
    # Optional setting for the date component separator
    my $date_sep  = '';
    
    # Terminate the program if the argument passed
    # is not allowed to be a delimiter.
    my @delims = ('-', '_');
    if ($_[0]) {
        $date_sep = $_[0];
        my $is_correct_delim = grep $date_sep eq $_, @delims;
        croak "The date delimiter must be one of: [".join(', ', @delims)."]"
            unless $is_correct_delim;
    }
    
    # Construct and return a datetime hash.
    my $dt  = DateTime->now(time_zone => 'local');
    my $ymd = $dt->ymd($date_sep);
    my $hms = $dt->hms(($date_sep ? ':' : ''));
    (my $hm = $hms) =~ s/[0-9]{2}$//;
    
    my %datetimes = (
        none   => '', # Used for timestamp suppressing
        ymd    => $ymd,
        hms    => $hms,
        hm     => $hm,
        ymdhms => sprintf("%s%s%s", $ymd, ($date_sep ? ' ' : '_'), $hms),
        ymdhm  => sprintf("%s%s%s", $ymd, ($date_sep ? ' ' : '_'), $hm),
    );
    
    return %datetimes;
}


sub construct_range {
    # """Construct a range for both a list of decimals
    # and a list of integers."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $range_aref = shift;
    my $line_sref  = shift;
    
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $range_aref eq ARRAY;
    
    my $line;
    if ($line_sref and $$line_sref) {
        croak "The 2nd arg of [$sub_name] must be a scalar ref!"
            unless ref $line_sref eq SCALAR;
    }
    
    #
    # Terminate the program if more than one decimal point
    # has been passed for a single number.
    #
    foreach (@$range_aref) {
        if (/[.]{2,}/) {
            print $$line_sref ? "=> [$$line_sref]" : "";
            croak "More than one decimal point! Terminating";
        }
    }
    
    #
    # Check if the given list of numbers contains a decimal.
    # This affects many of the following statements.
    #
    my @num_of_decimals = grep /[.]/, @$range_aref;
    
    #
    # Pad "integer" 0 to the omitted for correct range construction.
    #
    if (@num_of_decimals) {
        foreach (@$range_aref) {
            s/(^[.][0-9]+)/0$1/ if /^[.][0-9]+/;
        }
    }
    
    #
    # Populate min, max, (and optionally) incre.
    # (Dependent on whether a decimal is involved)
    #
    my $range_num_input = @$range_aref;
    my($min, $incre, $max);
    
    if ($range_num_input == 3) {
        ($min, $incre, $max) = @$range_aref;
        #
        # Terminate the program if $max is zero.
        #
        if (not $max) {
            print $$line_sref ? "=> [$$line_sref]" : "";
            croak "The max entry must be \"nonzero\"! Terminating";
        }
        
        # Hooks to jump to the next conditional: For empty and zero $incre
        $incre = -1 if (
            not $incre               # For empty and 0
            or $incre =~ /^0{2,}$/   # For 00, 000, ...
            or $incre =~ /^0+[.]0+$/ # For 0.0, 0.00, 00.0, 00.00, ...
            or $incre =~ /^0+[.]$/   # For 0., 00., ...
                                     #  .0,  .00, ... were already converted to
                                     # 0.0, 0.00, ... at the "Pad integer 0".
        );
    }
    if ($range_num_input == 2 or $incre == -1) {
        ($min, $max) = @$range_aref[0, -1]; # Slicing for empty $incre
        
        # Define the increment.
        # (i)  For decimals, the longest decimal places are used.
        #      e.g. 0.1,  0.20 --> Increment: 0.01
        #           0.05, 0.2  --> Increment: 0.01
        #           0.3,  0.5  --> Increment: 0.1
        # (ii) For integers, the increment is 1.
        if (@num_of_decimals) {
            my $power_of_ten;
            my $power_of_ten_largest = 0;
            
            foreach (@$range_aref) {
                $power_of_ten = index((reverse $_), '.');
                $power_of_ten_largest = $power_of_ten > $power_of_ten_largest ?
                    $power_of_ten : $power_of_ten_largest;
            }
            $incre = 10**-$power_of_ten_largest;
        }
        elsif (not @num_of_decimals) {
            $incre = 1;
        }
    }
    unless ($range_num_input == 3 or $range_num_input == 2) {
        print $$line_sref ? "=> [$$line_sref]" : "";
        croak "We need 2 or 3 numbers to construct a range! Terminating";
    }
    
    #
    # Terminate the program if the number passed as the min
    # is bigger than the number passed as the max.
    #
    if ($min > $max) {
        print $$line_sref ? "=> [$$line_sref]" : "";
        croak "$min is bigger than $max! Terminating";
    }
    
    #
    # Find the lengthiest number to construct a convert.
    # (Dependent on whether a decimal is involved)
    #
    my $lengthiest = '';
    foreach (@$range_aref) {
        # If a decimal is contained, compare only the decimal places.
        s/[0-9]+[.]([0-9]+)/$1/ if @num_of_decimals;
        
        $lengthiest = $_ if length($_) > length($lengthiest);
    }
    
    #
    # Construct a zero-padded convert (in case the ranged numbers
    # are used as part of filenames).
    #
    my $conv = @num_of_decimals ? '%.'.length($lengthiest).'f' :
                                  '%0'.length($lengthiest).'d';
    
    #
    # Construct a range.
    #
    # > If a decimal is involved, increase the powers of 10 of the list of
    #   numbers by a equal factor such that the decimal with the largest decimal
    #   places becomes an integer.
    #   e.g. 0.10,0.001,0.11 => 100, 1, 110
    # > Also, make sure that the number becomes an integer.
    #   Just multiplying the power of 10 does not make the float
    #   an integer.
    # > The powers of 10 of the list of numbers will then be decreased
    #   to the original ones after range construction by a C-like for loop.
    #   This is done because floating numbers cannot be correctly compared.
    #
    if (@num_of_decimals) {
        foreach ($min, $incre, $max) {
            $_ *= 10**length($lengthiest);
            $_ = int $_;
        }
    }
    
    @$range_aref = (); # Empty the range array ref before its refilling.
    for (my $i=$min; $i<=$max; $i+=$incre) {
        push @$range_aref, sprintf(
            "$conv",
            (
                @num_of_decimals ?
                    $i / 10**length($lengthiest):
                    $i
            )
        );
    }
    
    return;
}


sub rm_duplicates {
    # """Remove duplicate items from an array."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $aref = shift;
    
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $aref eq ARRAY;
    
    my(%seen, @uniqued);
    @uniqued = grep !$seen{$_}++, @$aref;
    @$aref = @uniqued;
    
    return;
}


sub rm_empty {
    # """Remove empty items from an array."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $aref = shift;
    
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $aref eq ARRAY;
    
    my @nonempty = grep { !/^$/ } @$aref;
    @$aref = @nonempty;
    
    return;
}


sub calc_vol {
    # """Calculate a volume."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my($geom, @dims) = @_;
    my $vol;
    
    # Right circular cylinder (RCC)
    if ($geom =~ /rcc/i) {
        my($rad, $hgt) = @dims;
        $vol = PI * $rad**2 * $hgt;
    }
    
    # Truncated right circular cylinder cone (TRC)
    # a.k.a. A conical frustum, a frustum of a cone
    elsif ($geom =~ /trc/i) {
        my($rad1, $rad2, $hgt) = @dims;
        $vol = PI/3 * $rad1**2 + $rad1*$rad2 + $rad2**2 * $hgt;
    }
    
    else { say "[$sub_name] cannot calculate [$geom]."; }
    
    return $vol;
}


1;
__END__